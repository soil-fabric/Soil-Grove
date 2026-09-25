"
How many workers there are, and what happens to a work unit that could not commit.

The workers are driven straight through rather than forked wherever a test only wants to
know what they do -- a forked process turns an assertion into a wait. One test forks, and
that one is about forking.

What the dispatcher decides is the number, never who gets what. The second is the queue's
own and is tested where the mutex is.
"
Class {
	#name : #SoilQueueDispatchTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'queues'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueDispatchTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueDispatchTest >> drain: aQueue [
	"let the workers run out. They end by themselves as soon as nothing comes any more,
	which is what a stop does to them too"

	| deadline |
	aQueue requestStop.
	deadline := DateAndTime now + 5 seconds.
	[ aQueue workers isEmpty or: [ DateAndTime now > deadline ] ] whileFalse: [
		10 milliSeconds asDelay wait ]
]

{ #category : #helpers }
SoilQueueDispatchTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #accessing }
SoilQueueDispatchTest >> path [
	"a database of its own. This is the only test class here that forks, and a worker that
	outlives its test would otherwise meet the next one's database"

	^ 'soil-queue-dispatch-tests'
]

{ #category : #helpers }
SoilQueueDispatchTest >> put: aBlock [

	^ self inTransaction: [ :txn |
		(self descriptionIn: txn) add: (aBlock value: (txn root at: #target)) ]
]

{ #category : #helpers }
SoilQueueDispatchTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ | queue |
	  queue := ((self descriptionIn: txn) newInstanceIn: txn)
		supervisor: soil newResidentSupervisor;
		yourself.
	  queues add: queue.
	  queue ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueDispatchTest >> setUp [

	super setUp.
	queues := OrderedCollection new.
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
SoilQueueDispatchTest >> stateOf: aKey [

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) entryAt: aKey ifAbsent: [ nil ])
		ifNotNil: [ :entry | entry state ] ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueDispatchTest >> targetEffects [

	| txn |
	txn := soil newTransaction.
	^ [ (txn root at: #target) effects ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueDispatchTest >> tearDown [
	"a forked worker has to be out of its transaction before the database goes away, or it
	meets a closed one somewhere in the middle"

	queues do: [ :each | self drain: each ].
	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueDispatchTest >> testAConflictThatNeverResolvesIsNotHiddenForEver [
	"trying for ever would turn something that does not resolve into silence"

	| key queue |
	SoilQueueTestConflictingEntry conflictsToRaise: 99.
	key := self put: [ :target | SoilQueueTestConflictingEntry on: target ].
	queue := self queue.
	queue claim: key.
	self
		should: [ queue work: key ]
		raise: SoilObjectHasConcurrentChange.
	self
		assert: SoilQueueTestConflictingEntry attempts
		equals: queue conflictLimit
]

{ #category : #tests }
SoilQueueDispatchTest >> testAWorkerEndsWhenNothingComesAnyMore [
	"that is also how a stop reaches a worker -- nobody suspends it from outside"

	| queue worker |
	self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	queue := self queue.
	worker := SoilQueueWorker on: queue.
	queue workerStarting: worker.
	worker run.

	self assert: queue workers equals: #(  ).
	self assert: self targetEffects equals: #( #ran )
]

{ #category : #tests }
SoilQueueDispatchTest >> testAWriteConflictRunsTheSameWorkUnitAgain [
	"the worker was there and the work was fine, it just did not happen. So it happens
	again at once, from a fresh transaction, which is what makes the re-read happen"

	| key queue |
	SoilQueueTestConflictingEntry conflictsToRaise: 1.
	key := self put: [ :target | SoilQueueTestConflictingEntry on: target ].
	queue := self queue.
	queue claim: key.
	queue work: key.

	self assert: SoilQueueTestConflictingEntry attempts equals: 2.
	self assert: (self stateOf: key) equals: nil.
	"only the attempt that committed left a trace -- the other one was discarded with its
	transaction, which is what made the re-read happen"
	self assert: self targetEffects equals: #( #attempt )
]

{ #category : #tests }
SoilQueueDispatchTest >> testAnEntryWhoseWorkThrowsIsNotHandedStraightBack [
	"a thrown work unit discards its transaction, so the entry keeps saying claimed. If the
	scan handed a claimed entry out again, the next worker would get it at once and the one
	after that too -- a worker spinning on one broken entry for ever. It waits for the
	recovery pass instead."

	| key queue |
	SoilQueueTestConflictingEntry conflictsToRaise: 99.
	key := self put: [ :target | SoilQueueTestConflictingEntry on: target ].
	queue := self queue.
	(SoilQueueWorker on: queue) run.

	self assert: (self stateOf: key) equals: #claimed.
	self assert: SoilQueueTestConflictingEntry attempts equals: queue conflictLimit
]

{ #category : #tests }
SoilQueueDispatchTest >> testNoMoreWorkersThanTheLimit [
	"the number of waiting entries says how long the working takes, not how many workers
	are needed.

	Counted as started, not as running: a forked worker can work its way through and be
	gone again before the count is read. So they are not forked, and the test runs them"

	| queue started |
	self workerLimit: 2.
	5 timesRepeat: [
		self put: [ :target | SoilQueueTestRepeatingEntry on: target ] ].
	queue := SoilQueueTestUnforkedQueue from: self queue.
	queue runStep.
	started := queue workers.
	started do: [ :each | each run ].

	self assert: started size equals: 2.
	self assert: self targetEffects equals: (Array new: 5 withAll: #ran)
]

{ #category : #tests }
SoilQueueDispatchTest >> testNoWorkerIsStartedWhenNothingIsDue [
	"nothing on stock: a worker exists because there is work, not in case there might be"

	| queue |
	self put: [ :target |
		(SoilQueueTestRepeatingEntry on: target)
			eligibleAt: DateAndTime now + 1 hour;
			yourself ].
	queue := self queue.
	queue runStep.
	self assert: queue workers equals: #(  )
]

{ #category : #tests }
SoilQueueDispatchTest >> testTheDispatcherStartsAWorkerForDueWork [
	"the one test that forks, because forking is what it is about"

	| queue |
	self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	queue := self queue.
	queue runStep.
	self assert: queue workers size equals: 1.

	self waitUntil: [ queue workers isEmpty ].
	self assert: self targetEffects equals: #( #ran )
]

{ #category : #helpers }
SoilQueueDispatchTest >> waitUntil: aBlock [
	"a forked worker needs a moment, and a test that waits for ever is worse than one that
	fails"

	| deadline |
	deadline := DateAndTime now + 5 seconds.
	[ aBlock value ] whileFalse: [
		DateAndTime now > deadline ifTrue: [ ^ self fail: 'the worker did not finish' ].
		10 milliSeconds asDelay wait ]
]

{ #category : #helpers }
SoilQueueDispatchTest >> workerLimit: anInteger [

	self inTransaction: [ :txn |
		(self descriptionIn: txn) workerLimit: anInteger ]
]
