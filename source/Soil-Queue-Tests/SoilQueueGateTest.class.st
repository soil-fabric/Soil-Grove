"
A gate on the outlet of a lane (SoilQueue>>#gate:forLane:): what leaves the lane, how many
workers are started for it, and when the dispatcher is awake. A lane without one behaves as
it always did.

On a workspace with two lanes ordered by due time, #a and #b, and a grouped one, #groups.
The queue is made without a resident, and its workers are not forked.
"
Class {
	#name : #SoilQueueGateTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueGateTest >> assignIn: aSymbol of: aQueue [

	^ aQueue assignNextIn: (aQueue lane: aSymbol) preferring: nil
]

{ #category : #helpers }
SoilQueueGateTest >> gate: anInteger [

	^ SoilQueueTestGate new
		allowance: anInteger;
		yourself
]

{ #category : #helpers }
SoilQueueGateTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #accessing }
SoilQueueGateTest >> path [

	^ 'soil-queue-gate-tests'
]

{ #category : #helpers }
SoilQueueGateTest >> put: anInteger into: aSymbol [

	self put: anInteger into: aSymbol dueAt: clock now
]

{ #category : #helpers }
SoilQueueGateTest >> put: anInteger into: aSymbol dueAt: aDateAndTime [

	self inTransaction: [ :txn |
		| workspace |
		workspace := self workspaceIn: txn.
		anInteger timesRepeat: [
			workspace
				add: ((SoilQueueTestEntry on: 'work')
					readyAt: aDateAndTime;
					yourself)
				to: (workspace laneNamed: aSymbol) ] ]
]

{ #category : #helpers }
SoilQueueGateTest >> putGrouped: anInteger dueAt: aDateAndTime [
	"anInteger entries, each of a group of its own"

	self inTransaction: [ :txn |
		| workspace |
		workspace := self workspaceIn: txn.
		1 to: anInteger do: [ :each |
			workspace
				add: ((SoilQueueTestGroupedEntry on: 'work' group: each)
					readyAt: aDateAndTime;
					yourself)
				to: (workspace laneNamed: #groups) ] ]
]

{ #category : #helpers }
SoilQueueGateTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ SoilQueueTestUnforkedQueue from: ((SoilQueue
			onWorkspace: (self workspaceIn: txn)
			configuredFrom: (SoilQueueDescription new
				workerLimit: 3 forLane: #a;
				workerLimit: 3 forLane: #b;
				workerLimit: 3 forLane: #groups;
				yourself)
			in: txn)
		clock: clock;
		yourself) ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueGateTest >> setUp [

	super setUp.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 11 day: 18 hour: 12 minute: 0 second: 0 offset: Duration zero).
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot.
	self inTransaction: [ :txn |
		| workspace |
		workspace := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24 markerWidth: 1.
		workspace
			addLaneNamed: #a format: SoilQueueTimeOrderedKeyFormat new;
			addLaneNamed: #b format: SoilQueueTimeOrderedKeyFormat new;
			addLaneNamed: #groups format: SoilQueueGroupedKeyFormat new.
		txn root at: #queue put: workspace.
		txn makeRoot: workspace.
		workspace initializeIn: txn ]
]

{ #category : #helpers }
SoilQueueGateTest >> startedFor: aSymbol in: aQueue [

	^ aQueue started count: [ :each | each lane name = aSymbol ]
]

{ #category : #running }
SoilQueueGateTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueGateTest >> testAGateOfOneLaneDoesNotHoldUpAnother [

	| queue |
	self put: 2 into: #a.
	self put: 2 into: #b.
	queue := self queue.
	queue gate: (self gate: 0) forLane: #a.
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 0.
	self assert: (self startedFor: #b in: queue) equals: 2.
	self assert: (self assignIn: #b of: queue) notNil
]

{ #category : #tests }
SoilQueueGateTest >> testAGateOnAGroupedLane [

	| queue gate |
	self putGrouped: 2 dueAt: clock now.
	queue := self queue.
	gate := self gate: 0.
	gate opensAt: clock now + 5 seconds.
	queue gate: gate forLane: #groups.
	queue runStep.

	self assert: (self startedFor: #groups in: queue) equals: 0.
	self assert: queue wakeAt equals: clock now + 5 seconds.
	self assert: (self assignIn: #groups of: queue) equals: nil.
	gate allowance: 1.
	queue runStep.

	self assert: (self startedFor: #groups in: queue) equals: 1.
	self assert: (self assignIn: #groups of: queue) notNil.
	self assert: gate taken equals: 1
]

{ #category : #tests }
SoilQueueGateTest >> testAGateOpenedFromOutsideLetsTheEntryOut [

	| queue gate |
	self put: 1 into: #a.
	queue := self queue.
	gate := self gate: 0.
	queue gate: gate forLane: #a.
	self assert: (self assignIn: #a of: queue) equals: nil.
	gate allowance: 1.

	self assert: (self assignIn: #a of: queue) notNil.
	self assert: gate taken equals: 1
]

{ #category : #tests }
SoilQueueGateTest >> testAGateRestrictsTheWorkersStartedToItsAllowance [

	| queue |
	self put: 3 into: #a.
	queue := self queue.
	queue gate: (self gate: 1) forLane: #a.
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 1
]

{ #category : #tests }
SoilQueueGateTest >> testAGateSurvivesTheLanesBeingBuiltAgain [
	"a start builds the live lanes anew. The gate is the queue's, by the name of the lane"

	| queue before |
	self put: 1 into: #a.
	queue := self queue.
	queue gate: (self gate: 0) forLane: #a.
	before := queue lane: #a.
	self inTransaction: [ :txn |
		queue configureFrom: SoilQueueDescription new in: txn ].

	self deny: (queue lane: #a) == before.
	self assert: (self assignIn: #a of: queue) equals: nil.
	queue runStep.
	self assert: (self startedFor: #a in: queue) equals: 0
]

{ #category : #tests }
SoilQueueGateTest >> testAGateThatCannotSayWhenItOpensGivesNoWakeTimeForDueWork [
	"unknown is not 'now': a time to wake at that is made up would have the dispatcher
	step and step again"

	| queue |
	self put: 1 into: #a.
	queue := self queue.
	queue gate: (self gate: 0) forLane: #a.
	queue runStep.

	self assert: queue wakeAt equals: nil
]

{ #category : #tests }
SoilQueueGateTest >> testALaneWithoutAGateIsUnchanged [

	| queue |
	self put: 3 into: #a.
	queue := self queue.
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 3.
	3 timesRepeat: [ self assert: (self assignIn: #a of: queue) notNil ].
	self assert: (self assignIn: #a of: queue) equals: nil
]

{ #category : #tests }
SoilQueueGateTest >> testAShutGateGivesNothingOutAndStartsNoWorker [

	| queue gate |
	self put: 2 into: #a.
	queue := self queue.
	gate := self gate: 0.
	queue gate: gate forLane: #a.
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 0.
	self assert: (self assignIn: #a of: queue) equals: nil.
	self assert: gate taken equals: 0
]

{ #category : #tests }
SoilQueueGateTest >> testAShutGateWakesAtTheTimeOfWorkDueAfterItOpens [
	"due in an hour, the gate opens in ten seconds: the hour is the time"

	| queue gate |
	self put: 1 into: #a dueAt: clock now + 1 hour.
	queue := self queue.
	gate := self gate: 0.
	gate opensAt: clock now + 10 seconds.
	queue gate: gate forLane: #a.
	queue runStep.

	self assert: queue wakeAt equals: clock now + 1 hour
]

{ #category : #tests }
SoilQueueGateTest >> testAShutGateWakesNoEarlierThanItOpensForWorkDueLater [
	"due in a second, the gate opens in ten: the entry cannot go before"

	| queue gate |
	self put: 1 into: #a dueAt: clock now + 1 second.
	queue := self queue.
	gate := self gate: 0.
	gate opensAt: clock now + 10 seconds.
	queue gate: gate forLane: #a.
	queue runStep.

	self assert: queue wakeAt equals: clock now + 10 seconds
]

{ #category : #tests }
SoilQueueGateTest >> testAShutGateWakesTheDispatcherWhenItOpensForDueWork [

	| queue gate |
	self put: 2 into: #a.
	queue := self queue.
	gate := self gate: 0.
	gate opensAt: clock now + 10 seconds.
	queue gate: gate forLane: #a.
	queue runStep.

	self assert: queue wakeAt equals: clock now + 10 seconds
]

{ #category : #tests }
SoilQueueGateTest >> testNextDueTimeIgnoresTheGate [
	"it says when something is due, and not when it may leave: a database with due entries
	held back by a gate counts as busy"

	| queue |
	self put: 1 into: #a.
	queue := self queue.
	queue gate: (self gate: 0) forLane: #a.

	self assert: queue nextDueTime equals: clock now
]

{ #category : #tests }
SoilQueueGateTest >> testTakeIsCalledOncePerEntryAndNeverForNothing [

	| queue gate |
	queue := self queue.
	gate := self gate: 5.
	queue gate: gate forLane: #a.
	self assert: (self assignIn: #a of: queue) equals: nil.
	self assert: gate taken equals: 0.

	self put: 1 into: #a dueAt: clock now + 1 hour.
	queue := self queue.
	queue gate: gate forLane: #a.
	self assert: (self assignIn: #a of: queue) equals: nil.
	self assert: gate taken equals: 0.

	self put: 2 into: #a.
	queue := self queue.
	queue gate: gate forLane: #a.
	3 timesRepeat: [ self assignIn: #a of: queue ].
	self assert: gate taken equals: 2
]

{ #category : #helpers }
SoilQueueGateTest >> workspaceIn: aTransaction [

	^ aTransaction root at: #queue
]
