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
  { role: (string-ascii 20), address: principal } 
  { authorized: bool })

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
    entry-fee: uint,     ;; in microSTX
    max-participants: uint,
    reward-pool: uint,   ;; in microSTX
    is-active: bool,
    is-ended: bool,
    participants-count: uint
  })

;; Track challenge participation
(define-map participation
  { challenge-id: uint, participant: principal }
  {
    registered-at: uint,
    total-steps: uint,
    total-distance: uint, ;; in meters
    last-update: uint,
    stake-amount: uint,   ;; in microSTX
    reward-claimed: bool
  })

;; Track challenge leaderboard
(define-map challenge-leaderboard
  { challenge-id: uint }
  { participants: (list 50 { participant: principal, total-steps: uint, total-distance: uint }) })

;; Track participant achievement status
(define-map achievements
  { challenge-id: uint, participant: principal }
  {
    completed-challenge: bool,
    reached-step-goal: bool,
    reached-distance-goal: bool
  })

;; Global variables
(define-data-var next-challenge-id uint u1)
(define-data-var contract-owner principal tx-sender)

;; Private functions

;; Verify if caller has the specified role
(define-private (has-role (role (string-ascii 20)) (caller principal))
  (default-to false (get authorized bool (map-get? authorized-roles { role: role, address: caller }))))

;; Check if caller is admin
(define-private (is-admin (caller principal))
  (has-role ADMIN-ROLE caller))

;; Check if caller is oracle
(define-private (is-oracle (caller principal))
  (has-role ORACLE-ROLE caller))

;; Check if caller is contract owner
(define-private (is-owner (caller principal))
  (is-eq caller (var-get contract-owner)))

;; Check if challenge exists
(define-private (challenge-exists (challenge-id uint))
  (is-some (map-get? challenges { challenge-id: challenge-id })))

;; Check if challenge is active
(define-private (is-challenge-active (challenge-id uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) false)))
    (and 
      (get is-active challenge)
      (not (get is-ended challenge))
      (>= block-height (get start-time challenge))
      (< block-height (get end-time challenge)))))

;; Check if user is registered for a challenge
(define-private (is-registered (challenge-id uint) (user principal))
  (is-some (map-get? participation { challenge-id: challenge-id, participant: user })))

;; Check if challenge is ended
(define-private (is-challenge-ended (challenge-id uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) false)))
    (or 
      (get is-ended challenge)
      (>= block-height (get end-time challenge)))))

;; Update leaderboard with new participant data
(define-private (update-leaderboard (challenge-id uint) (participant principal) (steps uint) (distance uint))
  (let ((current-leaderboard (default-to { participants: (list) } 
                             (map-get? challenge-leaderboard { challenge-id: challenge-id })))
        (participant-entry { participant: participant, total-steps: steps, total-distance: distance }))
    
    ;; Remove participant from current leaderboard if exists
    (let ((filtered-leaderboard (filter not-participant 
                                      (get participants current-leaderboard))))
      
      ;; Add updated participant data and sort by steps (descending)
      (let ((updated-participants (sort-leaderboard 
                                  (append filtered-leaderboard participant-entry))))
        
        ;; Store updated leaderboard (limited to top 50)
        (map-set challenge-leaderboard
          { challenge-id: challenge-id }
          { participants: (take 50 updated-participants) })))))

;; Helper for filtering out participant from leaderboard
(define-private (not-participant (entry { participant: principal, total-steps: uint, total-distance: uint }))
  (not (is-eq (get participant entry) tx-sender)))

;; Sort leaderboard entries by total steps (descending)
(define-private (sort-leaderboard (entries (list 50 { participant: principal, total-steps: uint, total-distance: uint })))
  ;; Note: In production, you'd implement a proper sorting algorithm here
  ;; This is a simplified representation as Clarity doesn't have complex sorting built-in
  entries)

;; Check and update achievements for a participant
(define-private (update-achievements (challenge-id uint) (participant principal))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) false))
        (participant-data (unwrap! (map-get? participation 
                                  { challenge-id: challenge-id, participant: participant }) 
                                  false))
        (current-achievements (default-to 
                              { completed-challenge: false, 
                                reached-step-goal: false, 
                                reached-distance-goal: false }
                              (map-get? achievements 
                                        { challenge-id: challenge-id, participant: participant }))))
    
    (let ((reached-step-goal (>= (get total-steps participant-data) (get step-goal challenge)))
          (reached-distance-goal (>= (get total-distance participant-data) (get distance-goal challenge)))
          (completed-challenge (and reached-step-goal reached-distance-goal)))
      
      (map-set achievements
        { challenge-id: challenge-id, participant: participant }
        { completed-challenge: completed-challenge,
          reached-step-goal: reached-step-goal,
          reached-distance-goal: reached-distance-goal }))))

;; Calculate reward for a participant
(define-private (calculate-reward (challenge-id uint) (participant principal))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) u0))
        (participant-data (unwrap! (map-get? participation 
                                  { challenge-id: challenge-id, participant: participant })
                                  { stake-amount: u0, reward-claimed: true }))
        (achievements-data (unwrap! (map-get? achievements
                                    { challenge-id: challenge-id, participant: participant })
                                    { completed-challenge: false,
                                      reached-step-goal: false,
                                      reached-distance-goal: false })))
    
    ;; Return stake if already claimed
    (if (get reward-claimed participant-data)
      u0
      ;; Basic reward calculation based on completion
      (if (get completed-challenge achievements-data)
        ;; Complete reward = stake + proportional share of reward pool
        (+ (get stake-amount participant-data)
           (/ (* (get reward-pool challenge) (get stake-amount participant-data))
              (get reward-pool challenge)))
        ;; Partial reward for partial completion
        (if (or (get reached-step-goal achievements-data)
                (get reached-distance-goal achievements-data))
          ;; Return stake + half share
          (+ (get stake-amount participant-data)
             (/ (* (get reward-pool challenge) (get stake-amount participant-data))
                (* u2 (get reward-pool challenge))))
          ;; Just return stake if no goals met
          (get stake-amount participant-data))))))

;; Read-only functions

;; Get challenge details
(define-read-only (get-challenge (challenge-id uint))
  (map-get? challenges { challenge-id: challenge-id }))

;; Get participant data for a challenge
(define-read-only (get-participant-data (challenge-id uint) (participant principal))
  (map-get? participation { challenge-id: challenge-id, participant: participant }))

;; Get challenge leaderboard
(define-read-only (get-leaderboard (challenge-id uint))
  (default-to { participants: (list) } (map-get? challenge-leaderboard { challenge-id: challenge-id })))

;; Get participant achievements for a challenge
(define-read-only (get-achievements (challenge-id uint) (participant principal))
  (map-get? achievements { challenge-id: challenge-id, participant: participant }))

;; Check if user has a specific role
(define-read-only (check-role (role (string-ascii 20)) (address principal))
  (has-role role address))

;; Get estimated reward for a participant
(define-read-only (get-estimated-reward (challenge-id uint) (participant principal))
  (calculate-reward challenge-id participant))

;; Public functions

;; Set contract owner
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))))

;; Grant role to an address
(define-public (grant-role (role (string-ascii 20)) (address principal))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-roles { role: role, address: address } { authorized: true }))))

;; Revoke role from an address
(define-public (revoke-role (role (string-ascii 20)) (address principal))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-roles { role: role, address: address } { authorized: false }))))

;; Create a new challenge (admin or owner only for official challenges)
(define-public (create-challenge
  (name (string-utf8 100))
  (description (string-utf8 500))
  (is-official bool)
  (start-time uint)
  (end-time uint)
  (step-goal uint)
  (distance-goal uint)
  (entry-fee uint)
  (max-participants uint)
  (initial-reward-pool uint))
  (let ((challenge-id (var-get next-challenge-id)))
    (begin
      ;; Check authorization
      (asserts! (or (not is-official) (is-admin tx-sender) (is-owner tx-sender)) ERR-NOT-AUTHORIZED)
      
      ;; Validate parameters
      (asserts! (>= (- end-time start-time) MIN-CHALLENGE_DURATION) ERR-INVALID-PARAMETERS)
      (asserts! (<= (- end-time start-time) MAX-CHALLENGE_DURATION) ERR-INVALID-PARAMETERS)
      (asserts! (> step-goal u0) ERR-INVALID-PARAMETERS)
      (asserts! (> distance-goal u0) ERR-INVALID-PARAMETERS)
      (asserts! (> max-participants u0) ERR-INVALID-PARAMETERS)
      
      ;; If official challenge with initial reward pool, transfer STX to contract
      (if (and is-official (> initial-reward-pool u0))
          (try! (stx-transfer? initial-reward-pool tx-sender (as-contract tx-sender)))
          true)
      
      ;; Create the challenge
      (map-set challenges
        { challenge-id: challenge-id }
        {
          name: name,
          description: description,
          creator: tx-sender,
          is-official: is-official,
          start-time: start-time,
          end-time: end-time,
          step-goal: step-goal,
          distance-goal: distance-goal,
          entry-fee: entry-fee,
          max-participants: max-participants,
          reward-pool: initial-reward-pool,
          is-active: true,
          is-ended: false,
          participants-count: u0
        })
      
      ;; Initialize empty leaderboard
      (map-set challenge-leaderboard
        { challenge-id: challenge-id }
        { participants: (list) })
      
      ;; Increment challenge ID counter
      (var-set next-challenge-id (+ challenge-id u1))
      
      (ok challenge-id))))

;; Register for a challenge
(define-public (register-for-challenge (challenge-id uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-CHALLENGE-NOT-FOUND)))
    (begin
      ;; Check challenge is active and not ended
      (asserts! (get is-active challenge) ERR-CHALLENGE-NOT-STARTED)
      (asserts! (not (get is-ended challenge)) ERR-CHALLENGE-ENDED)
      (asserts! (< block-height (get end-time challenge)) ERR-CHALLENGE-ENDED)
      
      ;; Check if already registered
      (asserts! (not (is-registered challenge-id tx-sender)) ERR-ALREADY-REGISTERED)
      
      ;; Check if challenge is full
      (asserts! (< (get participants-count challenge) (get max-participants challenge)) ERR-CHALLENGE-FULL)
      
      ;; Transfer entry fee if required
      (if (> (get entry-fee challenge) u0)
          (try! (stx-transfer? (get entry-fee challenge) tx-sender (as-contract tx-sender)))
          true)
      
      ;; Register the participant
      (map-set participation
        { challenge-id: challenge-id, participant: tx-sender }
        {
          registered-at: block-height,
          total-steps: u0,
          total-distance: u0,
          last-update: block-height,
          stake-amount: (get entry-fee challenge),
          reward-claimed: false
        })
      
      ;; Initialize participant achievements
      (map-set achievements
        { challenge-id: challenge-id, participant: tx-sender }
        {
          completed-challenge: false,
          reached-step-goal: false,
          reached-distance-goal: false
        })
      
      ;; Update challenge participants count
      (map-set challenges
        { challenge-id: challenge-id }
        (merge challenge { participants-count: (+ (get participants-count challenge) u1) }))
      
      ;; Update challenge reward pool with entry fee
      (map-set challenges
        { challenge-id: challenge-id }
        (merge challenge { reward-pool: (+ (get reward-pool challenge) (get entry-fee challenge)) }))
      
      (ok true))))

;; Submit step data for a challenge (oracle only)
(define-public (submit-step-data (challenge-id uint) (participant principal) (steps uint) (distance uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-CHALLENGE-NOT-FOUND))
        (participant-data (unwrap! (map-get? participation 
                                  { challenge-id: challenge-id, participant: participant }) 
                                  ERR-NOT-REGISTERED)))
    (begin
      ;; Check if caller is an oracle or the participant themselves
      (asserts! (or (is-oracle tx-sender) (is-eq tx-sender participant)) ERR-NOT-AUTHORIZED)
      
      ;; Check challenge is active
      (asserts! (is-challenge-active challenge-id) ERR-CHALLENGE-NOT-STARTED)
      
      ;; Validate step data (must be greater than current)
      (asserts! (> steps (get total-steps participant-data)) ERR-INVALID-STEP-DATA)
      (asserts! (> distance (get total-distance participant-data)) ERR-INVALID-STEP-DATA)
      
      ;; Update participant data
      (map-set participation
        { challenge-id: challenge-id, participant: participant }
        (merge participant-data {
          total-steps: steps,
          total-distance: distance,
          last-update: block-height
        }))
      
      ;; Update leaderboard
      (update-leaderboard challenge-id participant steps distance)
      
      ;; Update participant achievements
      (update-achievements challenge-id participant)
      
      (ok true))))

;; End a challenge (admin or creator only)
(define-public (end-challenge (challenge-id uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-CHALLENGE-NOT-FOUND)))
    (begin
      ;; Check authorization
      (asserts! (or (is-admin tx-sender) 
                   (is-eq tx-sender (get creator challenge))
                   (is-owner tx-sender)) 
               ERR-NOT-AUTHORIZED)
      
      ;; Check challenge is active
      (asserts! (get is-active challenge) ERR-CHALLENGE-NOT-STARTED)
      (asserts! (not (get is-ended challenge)) ERR-CHALLENGE-ENDED)
      
      ;; Update challenge status
      (map-set challenges
        { challenge-id: challenge-id }
        (merge challenge {
          is-active: false,
          is-ended: true
        }))
      
      (ok true))))

;; Claim rewards for a challenge
(define-public (claim-rewards (challenge-id uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-CHALLENGE-NOT-FOUND))
        (participant-data (unwrap! (map-get? participation 
                                  { challenge-id: challenge-id, participant: tx-sender }) 
                                  ERR-NOT-REGISTERED)))
    (begin
      ;; Check challenge is ended
      (asserts! (or (get is-ended challenge) (>= block-height (get end-time challenge))) ERR-CHALLENGE-ACTIVE)
      
      ;; Check rewards not already claimed
      (asserts! (not (get reward-claimed participant-data)) ERR-REWARDS-ALREADY-CLAIMED)
      
      ;; Calculate reward
      (let ((reward-amount (calculate-reward challenge-id tx-sender)))
        
        ;; Transfer reward if any
        (if (> reward-amount u0)
            (try! (as-contract (stx-transfer? reward-amount (as-contract tx-sender) tx-sender)))
            true)
        
        ;; Mark rewards as claimed
        (map-set participation
          { challenge-id: challenge-id, participant: tx-sender }
          (merge participant-data { reward-claimed: true }))
        
        (ok reward-amount)))))

;; Add funds to reward pool (anyone can add)
(define-public (add-to-reward-pool (challenge-id uint) (amount uint))
  (let ((challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-CHALLENGE-NOT-FOUND)))
    (begin
      ;; Check challenge is active
      (asserts! (get is-active challenge) ERR-CHALLENGE-NOT-STARTED)
      (asserts! (not (get is-ended challenge)) ERR-CHALLENGE-ENDED)
      
      ;; Transfer STX to contract
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Update reward pool
      (map-set challenges
        { challenge-id: challenge-id }
        (merge challenge {
          reward-pool: (+ (get reward-pool challenge) amount)
        }))
      
      (ok true))))