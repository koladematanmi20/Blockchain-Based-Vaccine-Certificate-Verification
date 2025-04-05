;; Vaccination Record Contract
;; Stores immunization details securely on the blockchain

;; Define data maps for storing vaccination records
(define-map vaccination-records
  { patient-id: principal }
  {
    vaccines: (list 10 {
      vaccine-id: (string-utf8 50),
      vaccine-name: (string-utf8 100),
      manufacturer: (string-utf8 100),
      batch-number: (string-utf8 50),
      vaccination-date: uint,
      healthcare-provider: principal
    })
  }
)

;; Define data map for authorized healthcare providers
(define-map authorized-providers
  { provider-id: principal }
  { is-authorized: bool }
)

;; Define contract owner
(define-data-var contract-owner principal tx-sender)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED u1)
(define-constant ERR-ALREADY-EXISTS u2)
(define-constant ERR-NOT-FOUND u3)
(define-constant ERR-INVALID-INPUT u4)

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if caller is an authorized healthcare provider
(define-private (is-authorized-provider)
  (default-to false (get is-authorized (map-get? authorized-providers { provider-id: tx-sender })))
)

;; Add or update a healthcare provider's authorization
(define-public (set-provider-authorization (provider principal) (authorized bool))
  (begin
    (asserts! (is-contract-owner) (err ERR-NOT-AUTHORIZED))
    (ok (map-set authorized-providers { provider-id: provider } { is-authorized: authorized }))
  )
)

;; Add a new vaccination record
(define-public (add-vaccination-record
  (patient-id principal)
  (vaccine-id (string-utf8 50))
  (vaccine-name (string-utf8 100))
  (manufacturer (string-utf8 100))
  (batch-number (string-utf8 50))
  (vaccination-date uint))
  (begin
    (asserts! (or (is-contract-owner) (is-authorized-provider)) (err ERR-NOT-AUTHORIZED))

    (let ((current-records (default-to { vaccines: (list) } (map-get? vaccination-records { patient-id: patient-id })))
          (new-vaccine {
            vaccine-id: vaccine-id,
            vaccine-name: vaccine-name,
            manufacturer: manufacturer,
            batch-number: batch-number,
            vaccination-date: vaccination-date,
            healthcare-provider: tx-sender
          }))
      (ok (map-set vaccination-records
                   { patient-id: patient-id }
                   { vaccines: (unwrap! (as-max-len? (append (get vaccines current-records) new-vaccine) u10) (err ERR-INVALID-INPUT)) }))
    )
  )
)

;; Get vaccination record for a patient (only accessible by the patient or authorized providers)
(define-read-only (get-vaccination-record (patient-id principal))
  (begin
    (asserts! (or (is-eq tx-sender patient-id) (is-authorized-provider) (is-contract-owner)) (err ERR-NOT-AUTHORIZED))
    (ok (default-to { vaccines: (list) } (map-get? vaccination-records { patient-id: patient-id })))
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) (err ERR-NOT-AUTHORIZED))
    (ok (var-set contract-owner new-owner))
  )
)
