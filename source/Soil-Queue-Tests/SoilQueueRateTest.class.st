"
The rate at the outlet: no more than so many entries handed out in any period of so
long, however many are due. It belongs to the queue and not to the entry -- a thousand due
entries would otherwise go through a worker unbraked.

Three places have to know about it, and each test here is about one of them. The handing
out, which refuses once the period is used up. The dispatcher, which starts no worker for
work the rate would not let out anyway. And the wake time, which would otherwise read
'due now' off the ordering while nothing may go, and have the dispatcher sleep until
somebody happened to signal.

Driven on a clock that stands still until it is moved.
"
Class {
	#name : #SoilQueueRateTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueRateTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueRateTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueRateTest >> left [
	"how many entries are still in the ordering"

	| txn count |
	txn := soil newTransaction.
	count := 0.
	[ (self descriptionIn: txn) keysAndEntriesDo: [ :key :entry | count := count + 1 ] ]
		ensure: [ txn abort ].
	^ count
]

{ #category : #accessing }
SoilQueueRateTest >> path [

	^ 'soil-queue-rate-tests'
]

{ #category : #helpers }
SoilQueueRateTest >> putDue: anInteger [

	self inTransaction: [ :txn |
		anInteger timesRepeat: [
			(self descriptionIn: txn) add: ((SoilQueueTestEntry on: 'work')
				eligibleAt: clock now;
				yourself) ] ]
]

{ #category : #helpers }
SoilQueueRateTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		supervisor: soil newResidentSupervisor;
		clock: clock;
		yourself ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueRateTest >> rate: anInteger per: aDuration [

	self inTransaction: [ :txn |
		(self descriptionIn: txn) rateLimit: anInteger per: aDuration ]
]

{ #category : #running }
SoilQueueRateTest >> setUp [

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
		keySize: 24)
]

{ #category : #running }
SoilQueueRateTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueRateTest >> testARateHandsOutNoMoreThanItsLimitPerPeriod [

	| queue |
	self rate: 2 per: 1 minute.
	self putDue: 5.
	queue := self queue.
	(SoilQueueWorker on: queue) run.

	self assert: self left equals: 3.
	self assert: queue wakeAt equals: clock now + 1 minute
]

{ #category : #tests }
SoilQueueRateTest >> testTheDispatcherStartsNoWorkerTheRateWouldNotLetOut [
	"due entries and a used-up period: no worker, and a wake time for when the period has
	room again -- not 'due now', which would have nobody wake at all"

	| queue |
	self rate: 1 per: 1 minute.
	self putDue: 3.
	queue := self queue.
	(SoilQueueWorker on: queue) run.
	self assert: self left equals: 2.

	queue runStep.
	self assert: queue workers isEmpty.
	self assert: queue wakeAt equals: clock now + 1 minute
]

{ #category : #tests }
SoilQueueRateTest >> testThePeriodSlides [
	"any period of a minute, not the minute on the clock: what went out half a minute ago
	still counts half a minute from now"

	| queue |
	self rate: 2 per: 1 minute.
	self putDue: 1.
	queue := self queue.
	(SoilQueueWorker on: queue) run.

	clock advanceBy: 30 seconds.
	self putDue: 3.
	(SoilQueueWorker on: queue) run.
	self assert: self left equals: 2.
	self assert: queue wakeAt equals: clock now + 30 seconds.

	clock advanceBy: 30 seconds.
	(SoilQueueWorker on: queue) run.
	self assert: self left equals: 1
]

{ #category : #tests }
SoilQueueRateTest >> testWithoutARateEverythingDueIsHandedOut [

	self putDue: 5.
	(SoilQueueWorker on: self queue) run.
	self assert: self left equals: 0
]

{ #category : #tests }
SoilQueueRateTest >> testARateOfNothingIsRefused [

	| description |
	description := SoilQueueDescription new.
	self should: [ description rateLimit: 0 per: 1 minute ] raise: Error.
	self assert: description rateLimit isNil
]
