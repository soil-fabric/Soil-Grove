"
How many workers run at once, lane by lane: a worker pool is a count of places, every
lane draws on one, and lanes may share it.

On a workspace with two lanes, #a and #b, and a queue made on it without a resident, so
that the pools are set in code. The workers are not forked, and counted as started.
"
Class {
	#name : #SoilQueueWorkerPoolTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueWorkerPoolTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueWorkerPoolTest >> laneNamed: aSymbol prefix: anInteger [

	^ SoilQueueLaneDescription
		named: aSymbol
		range: (SoilPrefixRange prefix: anInteger width: 1 keySize: 24)
		format: SoilQueueTimeOrderedKeyFormat new
]

{ #category : #accessing }
SoilQueueWorkerPoolTest >> path [

	^ 'soil-queue-worker-pool-tests'
]

{ #category : #helpers }
SoilQueueWorkerPoolTest >> put: anInteger into: aSymbol [

	self inTransaction: [ :txn |
		| workspace |
		workspace := self workspaceIn: txn.
		anInteger timesRepeat: [
			workspace
				add: ((SoilQueueTestEntry on: 'work')
					eligibleAt: clock now;
					yourself)
				to: (workspace laneNamed: aSymbol) ] ]
]

{ #category : #helpers }
SoilQueueWorkerPoolTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ SoilQueueTestUnforkedQueue from: ((SoilQueue onWorkspace: (self workspaceIn: txn) in: txn)
		clock: clock;
		yourself) ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueWorkerPoolTest >> setUp [

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
SoilQueueWorkerPoolTest >> startedFor: aSymbol in: aQueue [

	^ aQueue started count: [ :each | each lane name = aSymbol ]
]

{ #category : #running }
SoilQueueWorkerPoolTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueWorkerPoolTest >> testALaneWithAPoolOfItsOwnIsNotCrowdedOut [
	"the reason for a pool of its own: a lane full of due work cannot take the places
	another lane needs"

	| queue |
	self put: 3 into: #a.
	self put: 3 into: #b.
	queue := self queue.
	(queue pool: #default) size: 2.
	(queue lane: #b) pool: (SoilQueueWorkerPool named: #b size: 1).
	queue runStep.

	self assert: (self startedFor: #a in: queue) equals: 2.
	self assert: (self startedFor: #b in: queue) equals: 1
]

{ #category : #tests }
SoilQueueWorkerPoolTest >> testAWorkerThatEndedGivesItsPlaceBack [
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
SoilQueueWorkerPoolTest >> testByDefaultAllLanesShareOnePool [
	"one pool for all lanes, the size of the description's worker limit -- the upper bound
	of the whole queue"

	| queue |
	self put: 3 into: #a.
	self put: 3 into: #b.
	queue := self queue.
	(queue pool: #default) size: 2.
	queue runStep.

	self assert: queue started size equals: 2.
	self assert: (queue lane: #a) pool identicalTo: (queue lane: #b) pool
]

{ #category : #tests }
SoilQueueWorkerPoolTest >> testNoPoolWithoutAPlace [

	self should: [ SoilQueueWorkerPool named: #none size: 0 ] raise: Error
]

{ #category : #helpers }
SoilQueueWorkerPoolTest >> workspaceIn: aTransaction [

	^ aTransaction root at: #queue
]
