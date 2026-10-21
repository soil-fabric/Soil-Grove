"
How many workers run at once, lane by lane: every lane has a worker limit, a count of
places of its own, and lanes share none.

On a workspace with two lanes, #a and #b, and a queue made on it without a resident, so
that the limits are set in code. The workers are not forked, and counted as started.
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

{ #category : #helpers }
SoilQueueWorkerLimitTest >> laneNamed: aSymbol prefix: anInteger [

	^ SoilQueueLaneDescription
		named: aSymbol
		range: (SoilPrefixRange prefix: anInteger width: 1 keySize: 24)
		format: SoilQueueTimeOrderedKeyFormat new
]

{ #category : #accessing }
SoilQueueWorkerLimitTest >> path [

	^ 'soil-queue-worker-limit-tests'
]

{ #category : #helpers }
SoilQueueWorkerLimitTest >> put: anInteger into: aSymbol [

	self inTransaction: [ :txn |
		| workspace |
		workspace := self workspaceIn: txn.
		anInteger timesRepeat: [
			workspace
				add: ((SoilQueueTestEntry on: 'work')
					readyAt: clock now;
					yourself)
				to: (workspace laneNamed: aSymbol) ] ]
]

{ #category : #helpers }
SoilQueueWorkerLimitTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ SoilQueueTestUnforkedQueue from: ((SoilQueue onWorkspace: (self workspaceIn: txn) in: txn)
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
		workspace := SoilQueueWorkspace
			index: ((SoilIndexedDictionary newWithBackend: SoilSkipList)
				keySize: 24;
				maxLevel: 16;
				yourself)
			keySize: 24
			lanes: { self laneNamed: #a prefix: 1. self laneNamed: #b prefix: 2 }.
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
SoilQueueWorkerLimitTest >> testALaneIsNotCrowdedOutByAnother [
	"the reason the places are a lane's own: a lane full of due work cannot take the places
	another lane needs"

	| queue |
	self put: 3 into: #a.
	self put: 3 into: #b.
	queue := self queue.
	(queue lane: #a) workerLimit: 2.
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 2.
	self assert: (self startedFor: #b in: queue) equals: 1
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

	self should: [ (SoilQueueLane named: #none) workerLimit: 0 ] raise: Error
]

{ #category : #helpers }
SoilQueueWorkerLimitTest >> workspaceIn: aTransaction [

	^ aTransaction root at: #queue
]
