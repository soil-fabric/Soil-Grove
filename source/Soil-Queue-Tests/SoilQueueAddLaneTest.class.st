"
A lane comes in by #addLane:format:, and the prefix is never the caller's: the workspace
hands out the next free one and keeps it across starts.

Room for more lanes than one is decided when the workspace is created, by its marker
width. A workspace without markers has one lane over the whole index and no room for a
second.
"
Class {
	#name : #SoilQueueAddLaneTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueAddLaneTest >> format [

	^ SoilQueueTimeOrderedKeyFormat new
]

{ #category : #helpers }
SoilQueueAddLaneTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueAddLaneTest >> left [

	| txn count |
	txn := soil newTransaction.
	count := 0.
	[ (self workspaceIn: txn) keysAndEntriesDo: [ :key :entry | count := count + 1 ] ]
		ensure: [ txn abort ].
	^ count
]

{ #category : #accessing }
SoilQueueAddLaneTest >> path [

	^ 'soil-queue-add-lane-tests'
]

{ #category : #helpers }
SoilQueueAddLaneTest >> put: anInteger into: aSymbol [

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
SoilQueueAddLaneTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ (SoilQueue onWorkspace: (self workspaceIn: txn) in: txn)
		clock: clock;
		yourself ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueAddLaneTest >> setUp [

	super setUp.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 9 day: 25 hour: 12 minute: 0 second: 0 offset: Duration zero).
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot
]

{ #category : #helpers }
SoilQueueAddLaneTest >> storeWorkspace: aQueueWorkspace [

	self inTransaction: [ :txn |
		txn root at: #queue put: aQueueWorkspace.
		txn makeRoot: aQueueWorkspace.
		aQueueWorkspace initializeIn: txn ]
]

{ #category : #running }
SoilQueueAddLaneTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueAddLaneTest >> testAWorkspaceWithoutMarkersHasNoRoomForASecondLane [
	"its one lane has the whole index, so there is no section left to give"

	| workspace |
	workspace := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24.
	self should: [ workspace addLaneNamed: #b format: self format ] raise: Error.
	self assert: (workspace lanes collect: [ :each | each name ]) equals: #( #default )
]

{ #category : #tests }
SoilQueueAddLaneTest >> testAnAddedLaneGetsTheNextFreePrefix [

	| workspace |
	workspace := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24 markerWidth: 1.
	workspace addLaneNamed: #b format: self format.
	workspace addLaneNamed: #c format: self format.
	self
		assert: (workspace lanes collect: [ :each | each name -> each range prefix ])
		equals: { #default -> 0. #b -> 1. #c -> 2 }
]

{ #category : #tests }
SoilQueueAddLaneTest >> testAnAddedLaneIsStored [
	"the prefix stays the lane's across starts: whoever reads the workspace afresh finds it"

	| txn lane |
	self storeWorkspace: (SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24 markerWidth: 1).
	self inTransaction: [ :t | (self workspaceIn: t) addLaneNamed: #b format: self format ].
	txn := soil newTransaction.
	[ lane := (self workspaceIn: txn) laneNamed: #b.
	  self assert: lane range prefix equals: 1.
	  self assert: lane range width equals: 1 ] ensure: [ txn abort ]
]

{ #category : #tests }
SoilQueueAddLaneTest >> testAnAddedLaneRunsAtOnce [
	"added on a running queue, the lane is handed out from right away -- a lane that took
	entries it would not hand out until the next start would only collect them"

	| queue |
	self storeWorkspace: (SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24 markerWidth: 1).
	queue := self queue.
	queue addLane: #b format: self format.
	self put: 2 into: #b.
	self put: 1 into: #default.

	(SoilQueueWorker on: queue lane: (queue lane: #b)) run.
	self assert: self left equals: 1
]

{ #category : #tests }
SoilQueueAddLaneTest >> testAnAddedLaneRunsLikeTheDefaultLane [
	"until the next start configures it, a new lane takes the values of the default lane
	and draws on its pool"

	| queue lane |
	self storeWorkspace: (SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24 markerWidth: 1).
	queue := self queue.
	queue defaultLane rateLimit: 1 per: 1 minute.
	lane := queue addLane: #b format: self format.
	self assert: lane pool identicalTo: queue defaultLane pool.

	self put: 3 into: #b.
	(SoilQueueWorker on: queue lane: lane) run.
	self assert: self left equals: 2
]

{ #category : #tests }
SoilQueueAddLaneTest >> testAPrefixSpaceRunsFull [
	"one byte of marker is room for 256 lanes, #default included"

	| workspace |
	workspace := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24 markerWidth: 1.
	1 to: 255 do: [ :i | workspace addLaneNamed: ('lane' , i printString) asSymbol format: self format ].
	self assert: workspace lanes last range prefix equals: 255.
	self should: [ workspace addLaneNamed: #oneTooMany format: self format ] raise: Error
]

{ #category : #tests }
SoilQueueAddLaneTest >> testNoTwoLanesOfOneName [

	| workspace |
	workspace := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24 markerWidth: 1.
	self should: [ workspace addLaneNamed: #default format: self format ] raise: Error.
	self assert: workspace lanes size equals: 1
]

{ #category : #helpers }
SoilQueueAddLaneTest >> workspaceIn: aTransaction [

	^ aTransaction root at: #queue
]
