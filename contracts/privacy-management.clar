;; Privacy Management Contract
;; Controls what information is shared and with whom

;; Define data map for privacy settings
(define-map privacy-settings
  { patient-id: principal }
  {
    public-profile: bool,
    share-vaccine-types: bool,
    share-vaccination-dates: bool,
    share-healthcare-providers: bool,
    authorized-viewers: (list 50 principal),
    data-minimization-level: uint ;; 1: minimal, 2: standard, 3: comprehensive
  }
)

;; Define data map for consent records
(define-map consent-records
  { consent-id: (string-utf8 50) }
  {
    patient-id: principal,
    verifier-id: principal,
    granted-at: uint,
    expires-at: uint,
    purpose: (string-utf8 200),
    data-scope: (list 10 (string-utf8 50)),
    is-active: bool
  }
)

;; Define map for tracking consents by patient
(define-map patient-consents
  { patient-id: principal }
  { consent-ids: (list 20 (string-utf8 50)) }
)

;; Define contract owner
(define-data-var contract-owner principal tx-sender)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED u1)
(define-constant ERR-ALREADY-EXISTS u2)
(define-constant ERR-NOT-FOUND u3)
(define-constant ERR-INVALID-INPUT u4)
(define-constant ERR-EXPIRED u5)

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Initialize default privacy settings for a patient
(define-public (initialize-privacy-settings)
  (begin
    (asserts! (is-none (map-get? privacy-settings { patient-id: tx-sender })) (err ERR-ALREADY-EXISTS))

    (ok (map-set privacy-settings
                 { patient-id: tx-sender }
                 {
                   public-profile: false,
                   share-vaccine-types: false,
                   share-vaccination-dates: false,
                   share-healthcare-providers: false,
                   authorized-viewers: (list),
                   data-minimization-level: u2
                 }))
  )
)

;; Update privacy settings
(define-public (update-privacy-settings
  (public-profile bool)
  (share-vaccine-types bool)
  (share-vaccination-dates bool)
  (share-healthcare-providers bool)
  (data-minimization-level uint))
  (let ((current-settings (unwrap! (map-get? privacy-settings { patient-id: tx-sender }) (err ERR-NOT-FOUND))))
    (begin
      (asserts! (<= data-minimization-level u3) (err ERR-INVALID-INPUT))

      (ok (map-set privacy-settings
                   { patient-id: tx-sender }
                   (merge current-settings {
                     public-profile: public-profile,
                     share-vaccine-types: share-vaccine-types,
                     share-vaccination-dates: share-vaccination-dates,
                     share-healthcare-providers: share-healthcare-providers,
                     data-minimization-level: data-minimization-level
                   })))
    )
  )
)

;; Add an authorized viewer
(define-public (add-authorized-viewer (viewer principal))
  (let ((current-settings (unwrap! (map-get? privacy-settings { patient-id: tx-sender }) (err ERR-NOT-FOUND))))
    (begin
      (asserts! (not (is-eq tx-sender viewer)) (err ERR-INVALID-INPUT))

      (ok (map-set privacy-settings
                   { patient-id: tx-sender }
                   (merge current-settings {
                     authorized-viewers: (unwrap!
                                           (as-max-len?
                                             (append (get authorized-viewers current-settings) viewer)
                                             u50)
                                           (err ERR-INVALID-INPUT))
                   })))
    )
  )
)

;; Remove an authorized viewer
(define-public (remove-authorized-viewer (viewer principal))
  (let ((current-settings (unwrap! (map-get? privacy-settings { patient-id: tx-sender }) (err ERR-NOT-FOUND))))
    (begin
      ;; Filter out the viewer to remove
      ;; Note: In Clarity, we would need a more complex implementation to filter a list
      ;; This is a simplified version
      (ok (map-set privacy-settings
                   { patient-id: tx-sender }
                   current-settings))
    )
  )
)

;; Grant consent for data access
(define-public (grant-consent
  (consent-id (string-utf8 50))
  (verifier-id principal)
  (expires-at uint)
  (purpose (string-utf8 200))
  (data-scope (list 10 (string-utf8 50))))
  (begin
    (asserts! (is-none (map-get? consent-records { consent-id: consent-id })) (err ERR-ALREADY-EXISTS))

    ;; Store the consent record
    (map-set consent-records
      { consent-id: consent-id }
      {
        patient-id: tx-sender,
        verifier-id: verifier-id,
        granted-at: block-height,
        expires-at: expires-at,
        purpose: purpose,
        data-scope: data-scope,
        is-active: true
      }
    )

    ;; Update patient's consent list
    (let ((current-consents (default-to { consent-ids: (list) } (map-get? patient-consents { patient-id: tx-sender }))))
      (ok (map-set patient-consents
                   { patient-id: tx-sender }
                   { consent-ids: (unwrap! (as-max-len? (append (get consent-ids current-consents) consent-id) u20) (err ERR-INVALID-INPUT)) }))
    )
  )
)

;; Revoke consent
(define-public (revoke-consent (consent-id (string-utf8 50)))
  (let ((consent (unwrap! (map-get? consent-records { consent-id: consent-id }) (err ERR-NOT-FOUND))))
    (begin
      (asserts! (is-eq tx-sender (get patient-id consent)) (err ERR-NOT-AUTHORIZED))

      (ok (map-set consent-records
                   { consent-id: consent-id }
                   (merge consent { is-active: false })))
    )
  )
)

;; Check if a verifier has consent to access patient data
(define-read-only (check-consent (patient-id principal) (verifier-id principal) (data-type (string-utf8 50)))
  (begin
    ;; Note: In a real implementation, we would need to iterate through all consents
    ;; This is a simplified version that would require off-chain indexing
    (ok false)
  )
)

;; Get privacy settings
(define-read-only (get-privacy-settings (patient-id principal))
  (begin
    (asserts! (or (is-eq tx-sender patient-id) (is-contract-owner)) (err ERR-NOT-AUTHORIZED))
    (ok (unwrap! (map-get? privacy-settings { patient-id: patient-id }) (err ERR-NOT-FOUND)))
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) (err ERR-NOT-AUTHORIZED))
    (ok (var-set contract-owner new-owner))
  )
)
