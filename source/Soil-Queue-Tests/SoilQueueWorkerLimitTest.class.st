"
How many workers run at once, lane by lane: every lane has a worker limit, a count of
places of its own, and lanes share none.

On a workspace with two lanes, #a and #b, besides an empty #default, and a queue made on
it without a resident, so that the limits come from a description handed to it. The
workers are not forked, and counted as started.
"
Class {
	#name : #SoilQueueWorkerLimitTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueWorkerLimitTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #accessing }
SoilQueueWorkerLimitTest >> path [

	^ 'soil-queue-worker-limit-tests'
]

{ #category : #helpers }
SoilQueueWorkerLimitTest >> put: anInteger into: aSymbol [

	self put: anInteger into: aSymbol dueAt: clock now
]

{ #category : #helpers }
SoilQueueWorkerLimitTest >> put: anInteger into: aSymbol dueAt: aDateAndTime [

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
SoilQueueWorkerLimitTest >> queue [

	^ self queueWith: SoilQueueDescription new
]

{ #category : #helpers }
SoilQueueWorkerLimitTest >> queueWith: aDescription [

	| txn |
	txn := soil newTransaction.
	^ [ SoilQueueTestUnforkedQueue from: ((SoilQueue
			onWorkspace: (self workspaceIn: txn)
			configuredFrom: aDescription
			in: txn)
		clock: clock;
		yourself) ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueWorkerLimitTest >> setUp [

	super setUp.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 9 day: 25 hour: 12 minute: 0 second: 0 offset: Duration zero).
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
			addLaneNamed: #b format: SoilQueueTimeOrderedKeyFormat new.
		txn root at: #queue put: workspace.
		txn makeRoot: workspace.
		workspace initializeIn: txn ]
]

{ #category : #helpers }
SoilQueueWorkerLimitTest >> startedFor: aSymbol in: aQueue [

	^ aQueue started count: [ :each | each lane name = aSymbol ]
]

{ #category : #running }
SoilQueueWorkerLimitTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testALaneFullOfDueWorkDoesNotHideTheTimeOfAnother [
	"#a has more due than its one place, #b something an hour from now. Taken together the
	earliest time was 'now', which is no time to wake at, and the hour of #b was lost with
	it: nothing would have woken the dispatcher for #b"

	| queue |
	self put: 3 into: #a.
	self put: 1 into: #b dueAt: clock now + 1 hour.
	queue := self queue.
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 1.
	self assert: (self startedFor: #b in: queue) equals: 0.
	self assert: queue wakeAt equals: clock now + 1 hour
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testAKeyThatIsOutAsksForNoWorker [
	"a worker is on it already. Two due, one of them out with the one worker running: the
	step starts one more, for the other, and not two"

	| queue running |
	self put: 2 into: #a.
	queue := self queueWith: (SoilQueueDescription new
		workerLimit: 3 forLane: #a;
		yourself).
	running := SoilQueueWorker on: queue lane: (queue lane: #a).
	queue workerStarting: running.
	self assert: (queue assignNextIn: (queue lane: #a) preferring: nil) notNil.
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 2
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testALaneIsNotCrowdedOutByAnother [
	"the reason the places are a lane's own: a lane full of due work cannot take the places
	another lane needs"

	| queue |
	self put: 3 into: #a.
	self put: 3 into: #b.
	queue := self queueWith: (SoilQueueDescription new
		workerLimit: 2 forLane: #a;
		yourself).
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 2.
	self assert: (self startedFor: #b in: queue) equals: 1
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testAWorkerThatEndsInAStopRaisesNoFlag [
	"it ended because the queue stopped handing out. A flag raised now would stay up, with
	no dispatcher left to take it down, and a stopped queue would never be quiet"

	| queue |
	self put: 1 into: #a.
	queue := self queue.
	queue requestStop.
	(SoilQueueWorker on: queue lane: (queue lane: #a)) run.

	self deny: queue hasPendingWork.
	self assert: queue basicIsIdle
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testAWorkerThatEndsLetsTheNextStepStartAnother [
	"the one place of #a is taken by a worker that is running dry: its last empty look began
	before the entry came in. The step in between finds no place free, and nothing is due
	later. What brings the next step is the worker's end, and that step starts a worker for
	the entry. Before, nothing did, and the entry waited for whatever came next.

	The ending worker is one of a lane from before a start: counted by its lane's name,
	handed nothing, because its lane is not one the queue hands out from"

	| queue ending |
	queue := self queue.
	ending := SoilQueueWorker on: queue lane: (SoilQueueLane named: #a configuredFrom: SoilQueueDescription new).
	queue workerStarting: ending.
	self put: 1 into: #a.
	queue runStep.
	self assert: (self startedFor: #a in: queue) equals: 1.
	self deny: queue runStrategy isDue.

	ending run.
	self assert: queue runStrategy isDue.
	queue runStep.
	self assert: (self startedFor: #a in: queue) equals: 2
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testAWorkerThatEndedGivesItsPlaceBack [
	"a place is taken for as long as the worker runs, and no longer"

	| queue |
	self put: 3 into: #a.
	queue := self queue.
	queue runStep.
	self assert: queue started size equals: 1.
	queue runStep.
	self assert: queue started size equals: 1.

	queue started first run.
	self put: 1 into: #a.
	queue runStep.
	self assert: queue started size equals: 2
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testAPlaceIsNotKeptForAWorkerThatCouldNotBeStarted [
	"it is registered before it is started, so that the place is taken from the moment it
	exists. When starting it fails, its #run never began and cannot give the place back, so
	the queue does"

	| queue |
	queue := SoilQueueTestUnstartableQueue from: self queue.
	self should: [ queue startWorkerFor: (queue lane: #a) ] raise: Error.
	self assert: queue workers equals: #(  ).
	self assert: (queue freePlacesIn: (queue lane: #a)) equals: 1
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testAWorkerThatNeverRanGivesItsPlaceBackWhenTheProcessesAreTerminated [
	"a worker that was terminated before its #run began never reaches the end of it, which is
	where a worker takes itself out. With a limit of one place that would be no worker at
	all for ever, and a queue that never says it is quiet"

	| queue |
	self put: 1 into: #a.
	queue := self queue.
	queue runStep.
	self assert: queue started size equals: 1.
	self assert: (queue freePlacesIn: (queue lane: #a)) equals: 0.
	self deny: queue basicIsIdle.
	queue terminateProcesses.
	self assert: queue workers equals: #(  ).
	self assert: (queue freePlacesIn: (queue lane: #a)) equals: 1.
	self assert: queue basicIsIdle
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testByDefaultEveryLaneHasOnePlaceOfItsOwn [
	"one, the cautious direction, and not shared: an upper bound for the whole queue there
	is only as the sum of its lanes'"

	| queue |
	self put: 3 into: #a.
	self put: 3 into: #b.
	queue := self queue.
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 1.
	self assert: (self startedFor: #b in: queue) equals: 1
]

{ #category : #tests }
SoilQueueWorkerLimitTest >> testNoLaneWithoutAPlace [
	"refused where it is set, for all lanes as for one"

	self should: [ SoilQueueDescription new workerLimit: 0 ] raise: Error.
	self should: [ SoilQueueDescription new workerLimit: 0 forLane: #a ] raise: Error
]

{ #category : #helpers }
SoilQueueWorkerLimitTest >> workspaceIn: aTransaction [

	^ aTransaction root at: #queue
]
