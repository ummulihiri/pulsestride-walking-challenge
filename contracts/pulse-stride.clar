;; PulseStride Walking Challenge Contract
;; This contract manages walking challenges, user participation, and reward distribution
;; for the PulseStride platform, enabling users to join walking competitions, track progress,
;; and earn rewards based on verified step data.
;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CHALLENGE-NOT-FOUND (err u101))
(define-constant ERR-CHALLENGE-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-PARAMETERS (err u103))
(define-constant ERR-ALREADY-REGISTERED (err u104))
(define-constant ERR-NOT-REGISTERED (err u105))
(define-constant ERR-INSUFFICIENT-STAKE (err u106))
(define-constant ERR-CHALLENGE-FULL (err u107))
(define-constant ERR-CHALLENGE-ENDED (err u108))
(define-constant ERR-CHALLENGE-NOT-STARTED (err u109))
(define-constant ERR-CHALLENGE-ACTIVE (err u110))
(define-constant ERR-INVALID-STEP-DATA (err u111))
(define-constant ERR-REWARDS-ALREADY-CLAIMED (err u112))
;; Constants
(define-constant ADMIN-ROLE "admin")
(define-constant ORACLE-ROLE "oracle")
(define-constant MIN-CHALLENGE_DURATION u86400) ;; 1 day in seconds
(define-constant MAX-CHALLENGE_DURATION u2592000) ;; 30 days in seconds
;; Data structures
;; Track authorized roles (admins and oracles)
(define-map authorized-roles
  {
    role: (string-ascii 20),
    address: principal,
  }
  { authorized: bool }
)
;; Challenge data
(define-map challenges
  { challenge-id: uint }
  {
    name: (string-utf8 100),
    description: (string-utf8 500),
    creator: principal,
    is-official: bool,
    start-time: uint,
    end-time: uint,
    step-goal: uint,
    distance-goal: uint, ;; in meters
    entry-fee: uint, ;; in microSTX
    max-participants: uint,
    reward-pool: uint, ;; in microSTX
    is-active: bool,
    is-ended: bool,
    participants-count: uint,
  }
)
;; Track challenge participation
(define-map participation
  {
    challenge-id: uint,
    participant: principal,
  }
  {
    registered-at: uint,
    total-steps: uint,
    total-distance: uint, ;; in meters
    last-update: uint,
    stake-amount: uint, ;; in microSTX
    reward-claimed: bool,
  }
)
;; Track challenge leaderboard
(define-map challenge-leaderboard
  { challenge-id: uint }
  { participants: (list 50 {
    participant: principal,
    total-steps: uint,
    total-distance: uint,
  }) }
)
;; Track participant achievement status
(define-map achievements
  {
    challenge-id: uint,
    participant: principal,
  }
  {
    completed-challenge: bool,
    reached-step-goal: bool,
    reached-distance-goal: bool,
  }
)
;; Global variables
(define-data-var next-challenge-id uint u1)
(define-data-var contract-owner principal tx-sender)
;; Private functions

;; Check if caller is contract owner
(define-private (is-owner (caller principal))
  (is-eq caller (var-get contract-owner))
)

;; Check if challenge exists
(define-private (challenge-exists (challenge-id uint))
  (is-some (map-get? challenges { challenge-id: challenge-id }))
)

;; Check if challenge is active
(define-private (is-challenge-active (challenge-id uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) false)))
    (and
      (get is-active challenge)
      (not (get is-ended challenge))
      (>= block-height (get start-time challenge))
      (< block-height (get end-time challenge))
    )
  )
)

;; Check if user is registered for a challenge
(define-private (is-registered
    (challenge-id uint)
    (user principal)
  )
  (is-some (map-get? participation {
    challenge-id: challenge-id,
    participant: user,
  }))
)

;; Check if challenge is ended
(define-private (is-challenge-ended (challenge-id uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) false)))
    (or
      (get is-ended challenge)
      (>= block-height (get end-time challenge))
    )
  )
)

;; Sort leaderboard entries by total steps (descending)
(define-private (sort-leaderboard (entries (list 50 {
  participant: principal,
  total-steps: uint,
  total-distance: uint,
})))
  ;; Note: In production, you'd implement a proper sorting algorithm here
  ;; This is a simplified representation as Clarity doesn't have complex sorting built-in
  entries
)

;; Check and update achievements for a participant
(define-private (update-achievements
    (challenge-id uint)
    (participant principal)
  )
  (let (
      (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) false))
      (participant-data (unwrap!
        (map-get? participation {
          challenge-id: challenge-id,
          participant: participant,
        })
        false
      ))
      (current-achievements (default-to {
        completed-challenge: false,
        reached-step-goal: false,
        reached-distance-goal: false,
      }
        (map-get? achievements {
          challenge-id: challenge-id,
          participant: participant,
        })
      ))
    )
    (let (
        (reached-step-goal (>= (get total-steps participant-data) (get step-goal challenge)))
        (reached-distance-goal (>= (get total-distance participant-data) (get distance-goal challenge)))
        (completed-challenge (and reached-step-goal reached-distance-goal))
      )
      (map-set achievements {
        challenge-id: challenge-id,
        participant: participant,
      } {
        completed-challenge: completed-challenge,
        reached-step-goal: reached-step-goal,
        reached-distance-goal: reached-distance-goal,
      })
    )
  )
)

;; Read-only functions
;; Get challenge details
(define-read-only (get-challenge (challenge-id uint))
  (map-get? challenges { challenge-id: challenge-id })
)

;; Get participant data for a challenge
(define-read-only (get-participant-data
    (challenge-id uint)
    (participant principal)
  )
  (map-get? participation {
    challenge-id: challenge-id,
    participant: participant,
  })
)

;; Get challenge leaderboard
(define-read-only (get-leaderboard (challenge-id uint))
  (default-to { participants: (list) }
    (map-get? challenge-leaderboard { challenge-id: challenge-id })
  )
)

;; Get participant achievements for a challenge
(define-read-only (get-achievements
    (challenge-id uint)
    (participant principal)
  )
  (map-get? achievements {
    challenge-id: challenge-id,
    participant: participant,
  })
)

;; Public functions
;; Set contract owner
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)

;; Grant role to an address
(define-public (grant-role
    (role (string-ascii 20))
    (address principal)
  )
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-roles {
      role: role,
      address: address,
    } { authorized: true }
    ))
  )
)

;; Revoke role from an address
(define-public (revoke-role
    (role (string-ascii 20))
    (address principal)
  )
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-roles {
      role: role,
      address: address,
    } { authorized: false }
    ))
  )
)


;; Register for a challenge
(define-public (register-for-challenge (challenge-id uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id })
      ERR-CHALLENGE-NOT-FOUND
    )))
    (begin
      ;; Check challenge is active and not ended
      (asserts! (get is-active challenge) ERR-CHALLENGE-NOT-STARTED)
      (asserts! (not (get is-ended challenge)) ERR-CHALLENGE-ENDED)
      (asserts! (< block-height (get end-time challenge)) ERR-CHALLENGE-ENDED)
      ;; Check if already registered
      (asserts! (not (is-registered challenge-id tx-sender))
        ERR-ALREADY-REGISTERED
      )
      ;; Check if challenge is full
      (asserts!
        (< (get participants-count challenge) (get max-participants challenge))
        ERR-CHALLENGE-FULL
      )
      ;; Transfer entry fee if required
      (if (> (get entry-fee challenge) u0)
        (try! (stx-transfer? (get entry-fee challenge) tx-sender
          (as-contract tx-sender)
        ))
        true
      )
      ;; Register the participant
      (map-set participation {
        challenge-id: challenge-id,
        participant: tx-sender,
      } {
        registered-at: block-height,
        total-steps: u0,
        total-distance: u0,
        last-update: block-height,
        stake-amount: (get entry-fee challenge),
        reward-claimed: false,
      })
      ;; Initialize participant achievements
      (map-set achievements {
        challenge-id: challenge-id,
        participant: tx-sender,
      } {
        completed-challenge: false,
        reached-step-goal: false,
        reached-distance-goal: false,
      })
      ;; Update challenge participants count
      (map-set challenges { challenge-id: challenge-id }
        (merge challenge { participants-count: (+ (get participants-count challenge) u1) })
      )
      ;; Update challenge reward pool with entry fee
      (map-set challenges { challenge-id: challenge-id }
        (merge challenge { reward-pool: (+ (get reward-pool challenge) (get entry-fee challenge)) })
      )
      (ok true)
    )
  )
)

;; Add funds to reward pool (anyone can add)
(define-public (add-to-reward-pool
    (challenge-id uint)
    (amount uint)
  )
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id })
      ERR-CHALLENGE-NOT-FOUND
    )))
    (begin
      ;; Check challenge is active
      (asserts! (get is-active challenge) ERR-CHALLENGE-NOT-STARTED)
      (asserts! (not (get is-ended challenge)) ERR-CHALLENGE-ENDED)
      ;; Transfer STX to contract
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      ;; Update reward pool
      (map-set challenges { challenge-id: challenge-id }
        (merge challenge { reward-pool: (+ (get reward-pool challenge) amount) })
      )
      (ok true)
    )
  )
)
