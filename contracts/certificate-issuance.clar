;; Certificate Issuance Contract
;; Creates verifiable digital proof of vaccination

;; Define data maps for storing certificates
(define-map vaccination-certificates
  { certificate-id: (string-utf8 50) }
  {
    patient-id: principal,
    vaccine-id: (string-utf8 50),
    issuer: principal,
    issue-date: uint,
    expiration-date: uint,
    signature: (buff 64),
    revoked: bool
  }
)

;; Define map for tracking certificates by patient
(define-map patient-certificates
  { patient-id: principal }
  { certificate-ids: (list 20 (string-utf8 50)) }
)

;; Define authorized issuers
(define-map authorized-issuers
  { issuer-id: principal }
  { is-authorized: bool }
)

;; Define contract owner
(define-data-var contract-owner principal tx-sender)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED u1)
(define-constant ERR-ALREADY-EXISTS u2)
(define-constant ERR-NOT-FOUND u3)
(define-constant ERR-INVALID-INPUT u4)
(define-constant ERR-EXPIRED u5)
(define-constant ERR-REVOKED u6)

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if caller is an authorized issuer
(define-private (is-authorized-issuer)
  (default-to false (get is-authorized (map-get? authorized-issuers { issuer-id: tx-sender })))
)

;; Add or update an issuer's authorization
(define-public (set-issuer-authorization (issuer principal) (authorized bool))
  (begin
    (asserts! (is-contract-owner) (err ERR-NOT-AUTHORIZED))
    (ok (map-set authorized-issuers { issuer-id: issuer } { is-authorized: authorized }))
  )
)

;; Issue a new vaccination certificate
(define-public (issue-certificate
  (certificate-id (string-utf8 50))
  (patient-id principal)
  (vaccine-id (string-utf8 50))
  (expiration-date uint)
  (signature (buff 64)))
  (begin
    (asserts! (or (is-contract-owner) (is-authorized-issuer)) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-none (map-get? vaccination-certificates { certificate-id: certificate-id })) (err ERR-ALREADY-EXISTS))

    ;; Store the certificate
    (map-set vaccination-certificates
      { certificate-id: certificate-id }
      {
        patient-id: patient-id,
        vaccine-id: vaccine-id,
        issuer: tx-sender,
        issue-date: block-height,
        expiration-date: expiration-date,
        signature: signature,
        revoked: false
      }
    )

    ;; Update patient's certificate list
    (let ((current-certs (default-to { certificate-ids: (list) } (map-get? patient-certificates { patient-id: patient-id }))))
      (ok (map-set patient-certificates
                   { patient-id: patient-id }
                   { certificate-ids: (unwrap! (as-max-len? (append (get certificate-ids current-certs) certificate-id) u20) (err ERR-INVALID-INPUT)) }))
    )
  )
)

;; Revoke a certificate
(define-public (revoke-certificate (certificate-id (string-utf8 50)))
  (let ((certificate (unwrap! (map-get? vaccination-certificates { certificate-id: certificate-id }) (err ERR-NOT-FOUND))))
    (begin
      (asserts! (or (is-contract-owner) (is-eq tx-sender (get issuer certificate))) (err ERR-NOT-AUTHORIZED))
      (ok (map-set vaccination-certificates
                   { certificate-id: certificate-id }
                   (merge certificate { revoked: true })))
    )
  )
)

;; Get certificate details
(define-read-only (get-certificate (certificate-id (string-utf8 50)))
  (ok (unwrap! (map-get? vaccination-certificates { certificate-id: certificate-id }) (err ERR-NOT-FOUND)))
)

;; Get all certificates for a patient
(define-read-only (get-patient-certificates (patient-id principal))
  (begin
    (asserts! (or (is-eq tx-sender patient-id) (is-authorized-issuer) (is-contract-owner)) (err ERR-NOT-AUTHORIZED))
    (ok (default-to { certificate-ids: (list) } (map-get? patient-certificates { patient-id: patient-id })))
  )
)

;; Verify if a certificate is valid
(define-read-only (verify-certificate (certificate-id (string-utf8 50)))
  (let ((certificate (unwrap! (map-get? vaccination-certificates { certificate-id: certificate-id }) (err ERR-NOT-FOUND))))
    (begin
      (asserts! (not (get revoked certificate)) (err ERR-REVOKED))
      (asserts! (< block-height (get expiration-date certificate)) (err ERR-EXPIRED))
      (ok true)
    )
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) (err ERR-NOT-AUTHORIZED))
    (ok (var-set contract-owner new-owner))
  )
)
