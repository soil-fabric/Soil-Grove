"
The wake time: an entry that is due later has to wake somebody when its time comes.

Two places learn when that is, and neither opens a transaction for it. A dispatcher step
reads it off the ordering it scans anyway; a worker that runs dry hears it from the queue
when nothing is handed out -- the scan that found nothing due found the next due time on
the way. The dispatcher then sleeps until then, or until something happens first: new
work, a stop, a worker reporting an earlier time.

Time is the queue's clock here, not the wall clock, so 'an hour later' costs nothing and
says exactly what it says. Everything is driven straight through except the two tests
about the sleeping dispatcher, which fork because the sleep is what they are about.
"
Class {
	#name : #SoilQueueWakeTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock',
		'queues'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueWakeTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueWakeTest >> entryDueIn: aDuration [

	^ (SoilQueueTestEntry on: 'work')
		eligibleAt: clock now + aDuration;
		yourself
]

{ #category : #helpers }
SoilQueueWakeTest >> keys [

	| txn keys |
	txn := soil newTransaction.
	keys := OrderedCollection new.
	[ (self descriptionIn: txn) keysAndEntriesDo: [ :key :entry | keys add: key ] ]
		ensure: [ txn abort ].
	^ keys asArray
]

{ #category : #accessing }
SoilQueueWakeTest >> path [
	"a database of its own, because two tests here fork"

	^ 'soil-queue-wake-tests'
]

{ #category : #helpers }
SoilQueueWakeTest >> postponingEntry [
	"due now by the test's clock, and an hour later once it has run"

	^ (SoilQueueTestPostponingEntry on: 'work' postponedBy: 1 hour)
		eligibleAt: clock now;
		yourself
]

{ #category : #helpers }
SoilQueueWakeTest >> put: anEntry [

	| txn |
	txn := soil newTransaction.
	^ [ | key |
	  key := (self descriptionIn: txn) add: anEntry.
	  txn commit.
	  key ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueWakeTest >> queue [
	"a live queue on the description, running on the test's clock"

	| txn |
	txn := soil newTransaction.
	^ [ | queue |
	  queue := ((self descriptionIn: txn) newInstanceIn: txn)
		supervisor: soil newResidentSupervisor;
		clock: clock;
		yourself.
	  queues add: queue.
	  queue ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueWakeTest >> setUp [

	super setUp.
	queues := OrderedCollection new.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 9 day: 24 hour: 12 minute: 0 second: 0 offset: Duration zero).
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot.
	soil addResidentDescription: (SoilQueueDescription
		named: #work
		timeOrderedWithBackend: SoilSkipList
		keySize: 24)
]

{ #category : #helpers }
SoilQueueWakeTest >> start: aQueue [

	| txn |
	txn := soil newTransaction.
	[ aQueue startIn: txn ] ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueWakeTest >> stateAndDueTimeAt: aKey [
	"read inside the transaction: an entry comes back as a proxy, and a proxy of an aborted
	transaction answers nothing"

	| txn |
	txn := soil newTransaction.
	^ [ | entry |
	  entry := (self descriptionIn: txn) entryAt: aKey.
	  { entry state. entry eligibleAt } ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueWakeTest >> tearDown [
	"a sleeping dispatcher has to be out of its loop before the database goes away"

	queues do: [ :each |
		each requestStop.
		self waitUntil: [ each hasRunningProcess not and: [ each workers isEmpty ] ] ].
	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueWakeTest >> testADispatcherStepRemembersWhenTheNextEntryFallsDue [

	| queue |
	self put: (self entryDueIn: 1 hour).
	queue := self queue.
	queue runStep.

	self assert: queue workers isEmpty.
	self assert: queue wakeAt equals: clock now + 1 hour
]

{ #category : #tests }
SoilQueueWakeTest >> testAMovedEntryRunsOnceItsNewTimeHasCome [

	| queue |
	self put: self postponingEntry.
	queue := self queue.
	(SoilQueueWorker on: queue) run.
	self assert: self keys size equals: 1.

	clock advanceBy: 1 hour.
	(SoilQueueWorker on: queue) run.
	self assert: self keys isEmpty
]

{ #category : #tests }
SoilQueueWakeTest >> testASleepingDispatcherStopsWhenAsked [
	"the sleep is a timed wait on the work signal, and a stop signals it -- cooperative,
	with nobody suspending anything"

	| queue |
	self put: (self entryDueIn: 1 hour).
	queue := self queue.
	self start: queue.
	self waitUntil: [ queue wakeAt notNil ].

	queue requestStop.
	self waitUntil: [ queue hasRunningProcess not ].
	self assert: queue isStopped
]

{ #category : #tests }
SoilQueueWakeTest >> testAStepForgetsAWakeTimeThatHasPassed [
	"otherwise a wake time in the past would have the dispatcher step, and step, and step"

	| queue |
	self put: (self entryDueIn: 1 hour).
	queue := self queue.
	queue runStep.
	clock advanceBy: 2 hours.
	self put: (self entryDueIn: 1 hour).
	(SoilQueueWorker on: queue) run.
	queue runStep.

	self assert: queue wakeAt equals: clock now + 1 hour
]

{ #category : #tests }
SoilQueueWakeTest >> testATickWakesTheDispatcherWhenItsTimeHasCome [
	"the wait is measured in the time that was left when it began. A clock that moves
	faster than that -- here the test's, in production a wall clock set forward -- is
	caught at the next tick, which lets the dispatcher look at the time again"

	| queue key |
	key := self put: (self entryDueIn: 1 hour).
	queue := self queue.
	self start: queue.
	self waitUntil: [ queue wakeAt notNil ].

	clock advanceBy: 1 hour.
	queue tick.
	self waitUntil: [ (self keys includes: key) not ]
]

{ #category : #tests }
SoilQueueWakeTest >> testAWorkerThatRunsDryHandsTheWakeTimeOn [
	"the dispatcher never took a step here. The worker's empty scan found the next due time
	on its way, and that is where the dispatcher hears it"

	| queue |
	self put: (self entryDueIn: 0 seconds).
	self put: (self entryDueIn: 1 hour).
	queue := self queue.
	self assert: queue wakeAt isNil.

	(SoilQueueWorker on: queue) run.
	self assert: queue wakeAt equals: clock now + 1 hour
]

{ #category : #tests }
SoilQueueWakeTest >> testAnEarlierEntryHandedInCutsTheWaitShort [
	"the notification after the commit is all it takes: the flag makes the dispatcher take
	a step, and the step reads the new first entry"

	| queue |
	self put: (self entryDueIn: 1 hour).
	queue := self queue.
	queue runStep.

	self put: (self entryDueIn: 10 minutes).
	queue noteWork.
	self assert: queue runStrategy isDue.
	queue runStep.
	self assert: queue wakeAt equals: clock now + 10 minutes
]

{ #category : #tests }
SoilQueueWakeTest >> testAnEntryThatGoesOnLaterMovesItsKey [
	"a claim leaves the key alone, a new due time cannot: the key is what sorts by it"

	| queue key |
	key := self put: self postponingEntry.
	queue := self queue.
	(SoilQueueWorker on: queue) runOnce.

	self deny: (self keys includes: key).
	self assert: self keys size equals: 1.
	self
		assert: (self stateAndDueTimeAt: self keys first)
		equals: { #pending. clock now + 1 hour }.
	self assert: queue wakeAt isNil.

	self assert: (SoilQueueWorker on: queue) runOnce isNil.
	self assert: queue wakeAt equals: clock now + 1 hour
]

{ #category : #tests }
SoilQueueWakeTest >> testNothingHeldMeansNoWakeTime [

	| queue |
	queue := self queue.
	queue runStep.

	self assert: queue wakeAt isNil.
	self assert: queue timeUntilWake isNil
]

{ #category : #tests }
SoilQueueWakeTest >> testTheDispatcherSleepsNoLongerThanUntilThen [

	| queue |
	self put: (self entryDueIn: 1 hour).
	queue := self queue.
	queue runStep.
	self assert: queue timeUntilWake equals: 1 hour.

	clock advanceBy: 20 minutes.
	self assert: queue timeUntilWake equals: 40 minutes.
	self deny: queue runStrategy isDue.

	clock advanceBy: 1 hour.
	self assert: queue timeUntilWake equals: Duration zero.
	self assert: queue runStrategy isDue
]

{ #category : #helpers }
SoilQueueWakeTest >> waitUntil: aBlock [
	"a forked process needs a moment, and a test that waits for ever is worse than one that
	fails"

	| deadline |
	deadline := DateAndTime now + 5 seconds.
	[ aBlock value ] whileFalse: [
		DateAndTime now > deadline ifTrue: [ ^ self fail: 'the queue did not get there' ].
		10 milliSeconds asDelay wait ]
]
