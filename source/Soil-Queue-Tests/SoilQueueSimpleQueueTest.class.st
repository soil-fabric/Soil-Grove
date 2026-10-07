"
A queue that nobody gave a time: no lanes beyond the first, and no entry that says when it
may run. What sorts an entry is the time it was put in, so the queue hands entries out in
the order they came, and an entry that has to be tried again goes to the back of it.

That is not a third kind of queue. It is the time ordered lane when nobody sets a delay,
and these tests are the proof: the design has to carry it without a special case.
Driven on a clock that stands still until it is moved.
"
Class {
	#name : #SoilQueueSimpleQueueTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueSimpleQueueTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueSimpleQueueTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #accessing }
SoilQueueSimpleQueueTest >> path [

	^ 'soil-queue-simple-tests'
]

{ #category : #helpers }
SoilQueueSimpleQueueTest >> put: aBlock using: aQueue [
	"aBlock builds the entry on the target read in the same transaction. The queue puts it
	in, and the clock moves a second on, so that no two entries share a time"

	self inTransaction: [ :txn |
		aQueue add: (aBlock value: (txn root at: #target)) in: txn ].
	clock advanceBy: 1 second
]

{ #category : #helpers }
SoilQueueSimpleQueueTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		supervisor: soil newResidentSupervisor;
		clock: clock;
		yourself ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueSimpleQueueTest >> setUp [

	super setUp.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 10 day: 7 hour: 12 minute: 0 second: 0 offset: Duration zero).
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
SoilQueueSimpleQueueTest >> targetEffects [

	| txn |
	txn := soil newTransaction.
	^ [ (txn root at: #target) effects ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueSimpleQueueTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueSimpleQueueTest >> testAnEntryIsReadyAtTheTimeItWasPutIn [
	"not at the time it was made: an entry can wait for its turn to be put in, and what sorts
	it is the time it came"

	| queue entry |
	entry := SoilQueueTestEntry new.
	self assert: entry readyAt isNil.
	clock advanceBy: 1 hour.
	queue := self queue.
	self inTransaction: [ :txn | queue add: entry in: txn ].
	self assert: entry readyAt equals: clock now
]

{ #category : #tests }
SoilQueueSimpleQueueTest >> testAnEntryThatSetsATimeKeepsIt [

	| queue entry later |
	later := clock now + 1 day.
	entry := SoilQueueTestEntry new
		readyAt: later;
		yourself.
	queue := self queue.
	self inTransaction: [ :txn | queue add: entry in: txn ].
	self assert: entry readyAt equals: later
]

{ #category : #tests }
SoilQueueSimpleQueueTest >> testEntriesComeOutInTheOrderTheyWerePutIn [

	| queue worker |
	queue := self queue.
	1 to: 3 do: [ :each |
		self put: [ :target | SoilQueueTestNumberedEntry on: target number: each ] using: queue ].
	worker := SoilQueueWorker on: queue.
	3 timesRepeat: [ worker runOnce ].
	self assert: self targetEffects equals: #( 1 2 3 )
]

{ #category : #tests }
SoilQueueSimpleQueueTest >> testAnEntryThatIsTriedAgainTakesItsPlaceAtTheBack [
	"with no delay to wait out: the entry that failed goes to the back of the queue and the
	ones that were waiting come first, so a retry waits as long as the queue is long. The
	first one put in is the one that fails once"

	| queue worker |
	self inTransaction: [ :txn |
		(self descriptionIn: txn) backoffBase: 0 seconds ].
	queue := self queue.
	self put: [ :target | SoilQueueTestFlakyEntry on: target failing: 1 ] using: queue.
	self put: [ :target | SoilQueueTestNumberedEntry on: target number: 2 ] using: queue.
	self put: [ :target | SoilQueueTestNumberedEntry on: target number: 3 ] using: queue.
	worker := SoilQueueWorker on: queue.
	4 timesRepeat: [ worker runOnce ].
	self assert: self targetEffects equals: #( 2 3 #ran )
]
