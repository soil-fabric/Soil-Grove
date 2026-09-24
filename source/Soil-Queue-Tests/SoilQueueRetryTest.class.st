"
What happens to an entry whose work unit throws.

The throwing transaction is gone, so everything here is the queue's bookkeeping in a
transaction of its own: ask the entry what the error means, and then either put it off
until later and count it, or give up on it. Giving up is a result and not a dead letter
-- the target learns of it through #giveUp:in:, and the entry is done.

The acceptance criterion of the block is #testAnEntryThatKeepsFailingGivesUpAfterItsBudget:
an entry with transient failures goes through the backoff, gives up correctly, and never
touches the counter for lost workers.

Driven on a clock that stands still until it is moved, so that a backoff is a statement
about time rather than a wait.
"
Class {
	#name : #SoilQueueRetryTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueRetryTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueRetryTest >> due: anEntry [
	"due now by the test's clock"

	^ anEntry
		eligibleAt: clock now;
		yourself
]

{ #category : #helpers }
SoilQueueRetryTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueRetryTest >> onlyEntry [
	"state, due time and the two counters of the one entry in the ordering, or nil when it
	has left it. Read inside the transaction, because an entry comes back as a proxy"

	| txn |
	txn := soil newTransaction.
	^ [ | found |
	  (self descriptionIn: txn) keysAndEntriesDo: [ :key :entry |
		found := { entry state. entry eligibleAt. entry failureRetries. entry orphanedRetries } ].
	  found ]
		ensure: [ txn abort ]
]

{ #category : #accessing }
SoilQueueRetryTest >> path [

	^ 'soil-queue-retry-tests'
]

{ #category : #helpers }
SoilQueueRetryTest >> put: aBlock [
	"aBlock builds the entry on the target read in the same transaction"

	^ self inTransaction: [ :txn |
		(self descriptionIn: txn) add: (self due: (aBlock value: (txn root at: #target))) ]
]

{ #category : #helpers }
SoilQueueRetryTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		supervisor: soil newResidentSupervisor;
		clock: clock;
		yourself ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueRetryTest >> setUp [

	super setUp.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 9 day: 24 hour: 12 minute: 0 second: 0 offset: Duration zero).
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot.
	soil addResidentDescription: (SoilQueueDescription
		named: #work
		timeOrderedWithBackend: SoilSkipList
		keySize: 24).
	self inTransaction: [ :txn |
		txn root at: #target put: SoilQueueTestTarget new ]
]

{ #category : #helpers }
SoilQueueRetryTest >> targetEffects [

	| txn |
	txn := soil newTransaction.
	^ [ (txn root at: #target) effects asArray ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueRetryTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueRetryTest >> testAFailureIsRememberedButCountsAsNoStepError [
	"a handled failure is no crash loop, and the step error count is what shows one. The
	error itself stays readable for diagnosis"

	| queue |
	self put: [ :target | SoilQueueTestFlakyEntry on: target failing: 1 ].
	queue := self queue.
	(SoilQueueWorker on: queue) runOnce.

	self assert: queue lastStepError messageText equals: 'the far side answered 503'.
	self assert: queue stepErrorCount equals: 0
]

{ #category : #tests }
SoilQueueRetryTest >> testAPermanentFailureGivesUpAtOnce [
	"the base says #permanent, so nothing is retried that nobody thought through"

	self put: [ :target | SoilQueueTestBrokenEntry on: target ].
	(SoilQueueWorker on: self queue) runOnce.

	self assert: self onlyEntry isNil.
	self
		assert: self targetEffects
		equals: { { #gaveUp. 'the far side refused the request'. 0. 0 } }
]

{ #category : #tests }
SoilQueueRetryTest >> testARetriableFailureIsTriedAgainAfterABackoff [

	| queue |
	self put: [ :target | SoilQueueTestFlakyEntry on: target failing: 1 ].
	queue := self queue.
	(SoilQueueWorker on: queue) run.

	self assert: self onlyEntry equals: { #pending. clock now + 1 second. 1. 0 }.
	self assert: queue wakeAt equals: clock now + 1 second.
	self assert: self targetEffects isEmpty.

	clock advanceBy: 1 second.
	(SoilQueueWorker on: queue) run.
	self assert: self onlyEntry isNil.
	self assert: self targetEffects equals: #( #ran )
]

{ #category : #tests }
SoilQueueRetryTest >> testAnEntryMayChooseItsOwnDelay [

	self put: [ :target | SoilQueueTestPatientEntry on: target failing: 5 ].
	(SoilQueueWorker on: self queue) runOnce.
	self assert: self onlyEntry second equals: clock now + 10 minutes
]

{ #category : #tests }
SoilQueueRetryTest >> testAnEntryThatKeepsFailingGivesUpAfterItsBudget [
	"the acceptance criterion: through the backoff, give up correctly, and the counter for
	lost workers stays where it was -- nobody went away, the far side kept failing"

	| queue |
	self put: [ :target | SoilQueueTestFlakyEntry on: target failing: 100 ].
	queue := self queue.
	#( 1 2 4 ) doWithIndex: [ :seconds :retries |
		(SoilQueueWorker on: queue) run.
		self
			assert: self onlyEntry
			equals: { #pending. clock now + seconds seconds. retries. 0 }.
		clock advanceBy: seconds seconds ].

	(SoilQueueWorker on: queue) run.
	self assert: self onlyEntry isNil.
	self
		assert: self targetEffects
		equals: { { #gaveUp. 'the far side answered 503'. 3. 0 } }
]

{ #category : #tests }
SoilQueueRetryTest >> testTheBackoffDoublesUpToItsCap [

	| description |
	description := SoilQueueDescription new
		backoffBase: 1 second;
		backoffCap: 5 seconds;
		yourself.
	self
		assert: ((1 to: 5) collect: [ :retries | description retryDelayAfter: retries ]) asArray
		equals: { 1 second. 2 seconds. 4 seconds. 5 seconds. 5 seconds }
]

{ #category : #tests }
SoilQueueRetryTest >> testTheDefaultsAreThreeRetriesFromOneSecondUpToAnHour [

	| description |
	description := SoilQueueDescription new.
	self assert: description failureRetryLimit equals: 3.
	self assert: description backoffBase equals: 1 second.
	self assert: description backoffCap equals: 1 hour
]
