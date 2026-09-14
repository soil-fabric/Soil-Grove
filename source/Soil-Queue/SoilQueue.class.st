"
Work that outlives the process which created it, handed out oldest-due first.

I am the live half, and I have to be: what I do is keep two workers off the same entry,
and that only works if every one of them talks to the same object. A database object
cannot be that -- two transactions materialize two of it, each with a mutex of its own
that excludes nobody. So the durable part is my description's and the coordinating part
is mine.

Being live as long as the database is open, carrying runtime state, and having a
persisted description is precisely what a resident is, so I am one. Nothing about that
forces a supervisor on anyone: created and not started, I still hand out entries, and
without a supervisor there are no competing workers for the mutex to arbitrate.

Mine are the mutex and the set of keys that are out. Keys, not entries -- an entry read
in the transaction that selected it would already be a snapshot of an older moment in
the transaction that works on it. For the same reason what I hand out is a key, and
whoever takes it opens a transaction of its own.

One work unit at a time for now. How many run at once is the dispatcher's question and
comes with the QueueWorker; the transaction boundaries below are already the ones that
several of them will keep.
"
Class {
	#name : #SoilQueue,
	#superclass : #SoilActiveResident,
	#instVars : [
		'name',
		'mutex',
		'inFlight'
	],
	#category : #'Soil-Queue'
}

{ #category : #accessing }
SoilQueue class >> soilTransientInstVars [
	"the inherited entries have to be repeated: a subclass declaration replaces its
	superclass's rather than adding to it, and a forgotten one would drag a process or a
	semaphore into a written graph"

	^ #( supervisor process workSignal runStrategy mutex inFlight )
]

{ #category : #adding }
SoilQueue >> add: anEntry in: aTransaction [
	"put an entry in, in the caller's transaction. Not coordinated -- two writers do not
	get in each other's way here, because each entry gets a key of its own"

	^ (self descriptionIn: aTransaction) add: anEntry
]

{ #category : #working }
SoilQueue >> assignNextDueAt: aDateAndTime in: aTransaction ifNone: aBlock [
	"hand out the oldest due entry that nobody else holds, and remember that it is out.

	Under the mutex, because this is where competing workers meet. What crosses the
	boundary is a key: the transaction this scanned in is not the one the work happens in."

	| key nextTime |
	key := mutex critical: [
		| found |
		found := (self descriptionIn: aTransaction)
			nextDueAt: aDateAndTime
			skipping: inFlight
			ifNone: [ :time | nextTime := time. nil ].
		found ifNotNil: [ inFlight add: found ].
		found ].
	^ key ifNil: [ aBlock cull: nextTime ]
]

{ #category : #working }
SoilQueue >> claim: aKey [
	"step 2 of a work unit: its own short transaction, committed before the work starts.
	Its only purpose is the crash case -- an entry found as claimed with no worker running
	was in the middle of something. It is not the mutual exclusion; under MVCC a claim
	written here is invisible to a transaction that is already open elsewhere."

	self withTransactionDo: [ :txn |
		((self descriptionIn: txn) entryAt: aKey) claimAt: DateAndTime now.
		txn commit ]
]

{ #category : #initialization }
SoilQueue >> initialize [

	super initialize.
	mutex := Mutex new.
	inFlight := Set new
]

{ #category : #testing }
SoilQueue >> isHolding: aKey [
	"whether an entry is out with someone right now. What tells an orphaned claim from a
	running one: an entry that says claimed and is not in here had its worker taken away"

	^ mutex critical: [ inFlight includes: aKey ]
]

{ #category : #accessing }
SoilQueue >> name [
	"carried rather than looked up: my name ends up in a process name and in status lines,
	and a transaction for a label would be one too many -- sometimes while another one is
	already open"

	^ name
]

{ #category : #accessing }
SoilQueue >> name: aSymbol [

	name := aSymbol
]

{ #category : #working }
SoilQueue >> release: aKey [
	"the entry is no longer out with anyone, whatever became of it"

	mutex critical: [ inFlight remove: aKey ifAbsent: [ nil ] ]
]

{ #category : #running }
SoilQueue >> runStep [
	"one work unit, and its transaction boundaries are the point.

	Selecting, claiming and working are three transactions, not one. The claim is
	committed before the work so that a crash in the middle is visible afterwards. The
	result and the removal from the ordering are one commit, so the state where the work
	wants to go on and no entry is left cannot arise. And the release happens whatever
	happened, or a thrown work unit would take its entry out of circulation until the
	image restarts."

	| key |
	key := self withTransactionDo: [ :txn |
		self assignNextDueAt: DateAndTime now in: txn ifNone: [ :time | nil ] ].
	key ifNil: [ ^ self ].
	[ self claim: key.
	  self work: key ]
		ensure: [ self release: key ]
]

{ #category : #accessing }
SoilQueue >> runStrategyClass [

	^ SoilSignalRunStrategy
]

{ #category : #working }
SoilQueue >> work: aKey [
	"step 3: the work unit, and what follows from what it answers, in one commit.

	#more leaves the entry where it is and only gives the claim back. Pushing it out to a
	later due time is backoff, and backoff is not part of this stage -- an entry that says
	it goes on becomes due again immediately, which is correct and merely impatient.

	A thrown work unit discards the whole transaction: the entry stays in the ordering and
	keeps saying claimed. Booking that as a failed attempt needs a transaction of its own
	and belongs with retry."

	self withTransactionDo: [ :txn |
		| description entry outcome |
		description := self descriptionIn: txn.
		entry := description entryAt: aKey.
		outcome := entry performIn: txn.
		outcome == #more
			ifTrue: [ entry releaseClaim ]
			ifFalse: [
				description removeKey: aKey.
				entry markDone ].
		txn commit ]
]
