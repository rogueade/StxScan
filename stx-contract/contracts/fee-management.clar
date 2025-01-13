
;; title: fee-management
;; version:
;; summary:
;; description:

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-fee (err u101))

;; Define data vars
(define-data-var fee-wallet principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
(define-data-var default-fee-rate uint u250) ;; 2.5% (stored as basis points)

;; Define data maps
(define-map merchant-fees principal uint)

;; Define read-only functions
(define-read-only (get-merchant-fee (merchant principal))
  (default-to (var-get default-fee-rate) (map-get? merchant-fees merchant))
)