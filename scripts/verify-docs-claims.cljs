#!/usr/bin/env nbb
;; verify-docs-claims — re-derive every number README.md and docs/operator-quickstart.md
;; state, from the tree itself, and fail when the tree and the prose disagree.
;;
;; Why this exists: the prose in this repository quotes counts, byte sizes and
;; absences ("the deploy script's source path is not in this tree"). Prose does
;; not notice when it stops being true. This does.
;;
;; Usage:  nbb scripts/verify-docs-claims.cljs [<dir>]     (<dir> FIRST, default ".")
;; Exit:   0 every claim holds · 1 a claim is false · 2 could not answer
;;
;; Exit 2 is not exit 0. A run that cannot read the tree reports UNDETERMINED and
;; exits 2, so "not measured" can never be mistaken for "measured and clean".

(require '["node:fs" :as fs]
         '["node:child_process" :as cp]
         '["node:crypto" :as crypto]
         '[clojure.string :as str])

(def root (or (first (remove #(str/starts-with? % "--") *command-line-args*)) "."))

;; ── the claims, as data ──────────────────────────────────────────────────────
;; Measured 2026-08-18 against cloud-itonami/app-ohanashi f5c85b4, and the source
;; tree etzhayyim/root aca35b2c that migration.edn names.
(def claims
  {:tracked-files      17
   :inherited-bytes    28044        ; the 13 files that came out of the extraction
   :source-bytes       27393        ; the 11 files migration.edn declares
   :added-after-extraction #{"README.edn" "migration.edn"}
   :added-by-this-round #{"README.md"
                          "docs/adr/0001-what-this-repository-actually-contains.edn"
                          "docs/operator-quickstart.md"
                          "scripts/verify-docs-claims.cljs"}
   :monorepo-path-refs 4            ; 3 in docs/ + 1 in the deploy script
   :deploy-cp-path     "projects/etzhayyim-project-ohanashi/aws/connect/lex-lambda/lambda_function.py"
   :risk-tokens-in-lambda 0         ; docs specify none|low|medium|high|critical; the code has none
   :swallowing-except  1            ; the bare `except Exception:` that hides a model failure
   :lambda-bytes       2844})

;; sha256 of the 11 files that came across from the source tree, so an edit to any
;; of them is reported rather than folded into a byte total.
(def preserved
  {"NOTICE"            "3b164b796de10dc4e639967b630f67afc88236cf5a5bf59f63e16a155a44b31e"
   "OWNERS"            "4f403b93a08eedec628f037df8a262ccdaedd0bb62a1c96cf21b95b29da124cd"
   "PROJECT.jsonld"    "95b358c95ebf6bf82af8d0ffcccd12fc9cd7c8a838d15b4dfe763315749d76ba"
   "aws/connect/lex-lambda/lambda_function.py" "393d06b49dc65e49fa36c5f6285e778f14dd411e95c3791bae90d2d4627df1ce"
   "docs/260225-amazon-connect-tokyo.md"        "c7e4b481bf4e5441636d1ef03d00ed0bbbb7dc03d23529fdef223275711b07c2"
   "docs/260225-connect-lex-ai-deploy.md"       "e5cafacccfac1258981c4c205368bcd8f008a8539dfa317834bba59c433e0f4c"
   "docs/260225-implementation-backlog.md"      "d36829482fdd3440b79b6a8c0e9b09f5e6b73fedc1c3a7c09f4ba26befb8e2c2"
   "docs/260225-mvp-api-wasmcloud-architecture.md" "b7e0e1dae005356ec39bed7f755903f33dd57629abd08bd9c3a4bce4fb52fdf3"
   "docs/260225-project-plan.md"                "1bc717a1939df97e66919256908146d4052588e965cda75ed32980cff4dcacc0"
   "scripts/260225-amazon-connect-tokyo-check.sh" "0a91382e223b5a3a5d48c1aa4509dfb9ca1ea6d713c3e864ed64158b92cabdae"
   "scripts/260225-deploy-connect-lex-ai.sh"      "deaa413fc20790db75ae71d6fbd8b13aa1f29b97fb72f5c11c1afd832145fa06"})

(def undetermined (atom []))
(def failures (atom []))

(defn undet! [msg] (swap! undetermined conj msg))

(defn tracked-files []
  (try
    (->> (.execSync cp "git ls-files" #js {:cwd root :encoding "utf8"})
         str/split-lines
         (remove str/blank?)
         vec)
    (catch :default e
      (undet! (str "git ls-files failed: " (.-message e)))
      nil)))

(defn slurp* [rel]
  (try (.readFileSync fs (str root "/" rel) "utf8")
       (catch :default _ nil)))

(defn bytes-of [rel]
  (try (.-size (.statSync fs (str root "/" rel)))
       (catch :default _ nil)))

(defn sha256 [rel]
  (try (-> (.createHash crypto "sha256")
           (.update (.readFileSync fs (str root "/" rel)))
           (.digest "hex"))
       (catch :default _ nil)))

(defn check! [label expected actual]
  (let [ok (= expected actual)]
    (println (str (if ok "PASS" "FAIL") "\t" (name label)
                  "\texpected=" (pr-str expected) "\tactual=" (pr-str actual)))
    (when-not ok (swap! failures conj label))
    ok))

;; ── run ──────────────────────────────────────────────────────────────────────
(let [files (tracked-files)]
  (when (nil? files)
    (println "UNDETERMINED\tcould not list tracked files")
    (js/process.exit 2))

  ;; evidence floor: an empty scan is never a pass.
  (println (str "SCANNED\t" (count files)))
  (when (zero? (count files))
    (println "UNDETERMINED\tscanned 0 files")
    (js/process.exit 2))

  (let [inherited (into (vec (keys preserved)) ["README.edn" "migration.edn"])
        sizes    (into {} (map (juxt identity bytes-of)) files)
        missing  (keep (fn [[f s]] (when (nil? s) f)) sizes)]
    (when (seq missing)
      (undet! (str "tracked but unreadable: " (str/join ", " missing))))

    (check! :tracked-files (:tracked-files claims) (count files))
    (check! :inherited-bytes (:inherited-bytes claims)
            (reduce + 0 (keep #(get sizes %) inherited)))
    (check! :lambda-bytes (:lambda-bytes claims)
            (get sizes "aws/connect/lex-lambda/lambda_function.py"))

    ;; custody: the 11 preserved files, byte-identical, plus exactly the 2 known additions
    (let [bad (keep (fn [[f want]]
                      (let [got (sha256 f)]
                        (when-not (= want got) (str f " " (or got "MISSING")))))
                    preserved)]
      (check! :preserved-files-unchanged [] (vec bad)))
    (check! :added-after-extraction (:added-after-extraction claims)
            (set (remove (into (set (keys preserved)) (:added-by-this-round claims)) files)))
    (check! :added-by-this-round (:added-by-this-round claims)
            (set (remove (into (set (keys preserved)) (:added-after-extraction claims)) files)))
    (check! :source-bytes (:source-bytes claims)
            (reduce + 0 (keep #(get sizes %) (keys preserved))))

    ;; the deploy script copies from a path that is not in this tree
    (check! :deploy-cp-path-absent true
            (nil? (bytes-of (:deploy-cp-path claims))))
    (check! :deploy-cp-path-still-cited true
            (boolean (some-> (slurp* "scripts/260225-deploy-connect-lex-ai.sh")
                             (str/includes? (:deploy-cp-path claims)))))

    ;; references to the pre-extraction monorepo layout, in the INHERITED files only.
    ;; README.md and the quickstart quote these paths on purpose, as defects; counting
    ;; those would make the number describe this round's prose instead of the repo.
    (check! :monorepo-path-refs (:monorepo-path-refs claims)
            (reduce + 0 (for [f inherited
                              :when (re-find #"\.(md|sh)$" f)
                              :let [t (slurp* f)]
                              :when t]
                          (count (re-seq #"60-apps/etzhayyim-project-ohanashi|projects/etzhayyim-project-ohanashi" t)))))

    ;; the safety gap: risk classification is specified in docs, absent in code
    (let [lam (slurp* "aws/connect/lex-lambda/lambda_function.py")]
      (if (nil? lam)
        (undet! "lambda_function.py unreadable")
        (do
          (check! :risk-tokens-in-lambda (:risk-tokens-in-lambda claims)
                  (count (re-seq #"(?i)risk" lam)))
          (check! :swallowing-except (:swallowing-except claims)
                  (count (re-seq #"except Exception" lam))))))))

(let [u @undetermined f @failures]
  (when (seq u)
    (doseq [m u] (println (str "UNDETERMINED\t" m)))
    (println "Refusing to report a pass: the tree could not be read completely.")
    (js/process.exit 2))
  (if (seq f)
    (do (println (str "FAILED\t" (count f) " claim(s): " (str/join ", " (map name f))))
        (js/process.exit 1))
    (do (println "OK\tevery claim in README.md and docs/operator-quickstart.md holds")
        (js/process.exit 0))))
