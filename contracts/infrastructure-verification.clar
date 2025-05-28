;; Infrastructure Verification Contract
;; Validates and manages traffic management systems

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_NOT_FOUND (err u102))
(define-constant ERR_INVALID_STATUS (err u103))

;; Infrastructure status types
(define-constant STATUS_PENDING u0)
(define-constant STATUS_VERIFIED u1)
(define-constant STATUS_REJECTED u2)
(define-constant STATUS_MAINTENANCE u3)

;; Data structures
(define-map infrastructure-registry
  { infrastructure-id: uint }
  {
    owner: principal,
    location: (string-ascii 100),
    infrastructure-type: (string-ascii 50),
    status: uint,
    verification-date: uint,
    last-maintenance: uint
  }
)

(define-map authorized-verifiers principal bool)

(define-data-var next-infrastructure-id uint u1)

;; Authorization functions
(define-public (add-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (ok (map-set authorized-verifiers verifier true))
  )
)

(define-public (remove-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (ok (map-delete authorized-verifiers verifier))
  )
)

;; Infrastructure management
(define-public (register-infrastructure (location (string-ascii 100)) (infrastructure-type (string-ascii 50)))
  (let ((infrastructure-id (var-get next-infrastructure-id)))
    (asserts! (is-none (map-get? infrastructure-registry { infrastructure-id: infrastructure-id })) ERR_ALREADY_EXISTS)
    (map-set infrastructure-registry
      { infrastructure-id: infrastructure-id }
      {
        owner: tx-sender,
        location: location,
        infrastructure-type: infrastructure-type,
        status: STATUS_PENDING,
        verification-date: u0,
        last-maintenance: u0
      }
    )
    (var-set next-infrastructure-id (+ infrastructure-id u1))
    (ok infrastructure-id)
  )
)

(define-public (verify-infrastructure (infrastructure-id uint) (approved bool))
  (let ((infrastructure (unwrap! (map-get? infrastructure-registry { infrastructure-id: infrastructure-id }) ERR_NOT_FOUND)))
    (asserts! (default-to false (map-get? authorized-verifiers tx-sender)) ERR_UNAUTHORIZED)
    (map-set infrastructure-registry
      { infrastructure-id: infrastructure-id }
      (merge infrastructure {
        status: (if approved STATUS_VERIFIED STATUS_REJECTED),
        verification-date: block-height
      })
    )
    (ok approved)
  )
)

(define-public (update-maintenance (infrastructure-id uint))
  (let ((infrastructure (unwrap! (map-get? infrastructure-registry { infrastructure-id: infrastructure-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq (get owner infrastructure) tx-sender) ERR_UNAUTHORIZED)
    (map-set infrastructure-registry
      { infrastructure-id: infrastructure-id }
      (merge infrastructure { last-maintenance: block-height })
    )
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-infrastructure (infrastructure-id uint))
  (map-get? infrastructure-registry { infrastructure-id: infrastructure-id })
)

(define-read-only (is-verified (infrastructure-id uint))
  (match (map-get? infrastructure-registry { infrastructure-id: infrastructure-id })
    infrastructure (is-eq (get status infrastructure) STATUS_VERIFIED)
    false
  )
)

(define-read-only (is-authorized-verifier (verifier principal))
  (default-to false (map-get? authorized-verifiers verifier))
)
