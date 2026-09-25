"
A lane goes by #removeLane:, and only when nothing is left in it: no entry, no dead letter,
no worker running. #removeLane:discardingEntries: with true takes its entries and dead
letters along, on purpose -- parked work is otherwise never deleted.

The default lane stays: the queue puts entries there that name no lane, and a lane added
at runtime runs like it.
"
Class {
	#name : #SoilQueueRemoveLaneTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueRemoveLaneTest >> deadLetterCount [

	| txn count |
	txn := soil newTransaction.
	count := 0.
	[ (self workspaceIn: txn) deadLettersDo: [ :key :entry | count := count + 1 ] ]
		ensure: [ txn abort ].
	^ count
]

{ #category : #helpers }
SoilQueueRemoveLaneTest >> deadLetterOneIn: aSymbol [

	self inTransaction: [ :txn |
		| workspace key |
		workspace := self workspaceIn: txn.
		key := workspace
			add: ((SoilQueueTestEntry on: 'work')
				eligibleAt: clock now;
				yourself)
			to: (workspace laneNamed: aSymbol).
		workspace deadLetter: key ]
]

{ #category : #helpers }
SoilQueueRemoveLaneTest >> format [

	^ SoilQueueTimeOrderedKeyFormat new
]

{ #category : #helpers }
SoilQueueRemoveLaneTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueRemoveLaneTest >> laneNamesOnDisk [

	| txn |
	txn := soil newTransaction.
	^ [ ((self workspaceIn: txn) lanes collect: [ :each | each name ]) asArray ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueRemoveLaneTest >> left [

	| txn count |
	txn := soil newTransaction.
	count := 0.
	[ (self workspaceIn: txn) keysAndEntriesDo: [ :key :entry | count := count + 1 ] ]
		ensure: [ txn abort ].
	^ count
]

{ #category : #accessing }
SoilQueueRemoveLaneTest >> path [

	^ 'soil-queue-remove-lane-tests'
]

{ #category : #helpers }
SoilQueueRemoveLaneTest >> put: anInteger into: aSymbol [

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
SoilQueueRemoveLaneTest >> queue [
	"a queue on the stored workspace, with a lane #b added to it"

	| txn queue |
	txn := soil newTransaction.
	queue := [ SoilQueueTestUnforkedQueue from: ((SoilQueue onWorkspace: (self workspaceIn: txn) in: txn)
		clock: clock;
		yourself) ]
		ensure: [ txn abort ].
	queue addLane: #b format: self format.
	^ queue
]

{ #category : #running }
SoilQueueRemoveLaneTest >> setUp [

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
		txn root at: #queue put: workspace.
		txn makeRoot: workspace.
		workspace initializeIn: txn ]
]

{ #category : #running }
SoilQueueRemoveLaneTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueRemoveLaneTest >> testALaneWithDeadLettersIsNotRemoved [
	"parked work is there to be looked at, and removing the lane would delete it"

	| queue |
	queue := self queue.
	self deadLetterOneIn: #b.
	self should: [ queue removeLane: #b ] raise: Error.
	self assert: self laneNamesOnDisk equals: #( #default #b ).
	self assert: self deadLetterCount equals: 1
]

{ #category : #tests }
SoilQueueRemoveLaneTest >> testALaneWithEntriesIsNotRemoved [

	| queue |
	queue := self queue.
	self put: 1 into: #b.
	self should: [ queue removeLane: #b ] raise: Error.

	self assert: self laneNamesOnDisk equals: #( #default #b ).
	self assert: (queue lanes collect: [ :each | each name ]) asArray equals: #( #default #b ).
	self assert: self left equals: 1
]

{ #category : #tests }
SoilQueueRemoveLaneTest >> testALaneWithRunningWorkersIsNotRemoved [
	"a worker of it may be in the middle of an entry. It runs dry by itself"

	| queue |
	queue := self queue.
	self put: 1 into: #b.
	queue runStep.
	self assert: (queue workers anySatisfy: [ :each | each lane name = #b ]).

	self should: [ queue removeLane: #b discardingEntries: true ] raise: Error.
	self assert: self laneNamesOnDisk equals: #( #default #b ).
	self assert: self left equals: 1
]

{ #category : #tests }
SoilQueueRemoveLaneTest >> testAnEmptyLaneIsRemoved [

	| queue |
	queue := self queue.
	queue removeLane: #b.

	self assert: self laneNamesOnDisk equals: #( #default ).
	self assert: (queue lanes collect: [ :each | each name ]) asArray equals: #( #default )
]

{ #category : #tests }
SoilQueueRemoveLaneTest >> testARemovedLanesMarkerIsGivenOutAgain [
	"nothing is left under it, so nothing can be mistaken for the new lane's"

	| queue txn |
	queue := self queue.
	queue addLane: #c format: self format.
	queue removeLane: #b.
	queue addLane: #d format: self format.

	txn := soil newTransaction.
	[ self assert: ((self workspaceIn: txn) laneNamed: #d) range prefix equals: 1 ]
		ensure: [ txn abort ]
]

{ #category : #tests }
SoilQueueRemoveLaneTest >> testAWorkerOfARemovedLaneFindsNothing [
	"the dispatcher may have started one for the lane just before it went. Nothing is handed
	out for a lane that is not there, so the worker ends as any worker does that runs dry"

	| queue worker |
	queue := self queue.
	worker := SoilQueueWorker on: queue lane: (queue lane: #b).
	queue removeLane: #b.
	self put: 1 into: #default.

	worker run.
	self assert: self left equals: 1
]

{ #category : #tests }
SoilQueueRemoveLaneTest >> testDiscardingTakesEntriesAndDeadLettersAlong [

	| queue |
	queue := self queue.
	self put: 2 into: #b.
	self deadLetterOneIn: #b.
	self deadLetterOneIn: #default.
	self put: 1 into: #default.

	queue removeLane: #b discardingEntries: true.
	self assert: self laneNamesOnDisk equals: #( #default ).
	self assert: self left equals: 1.
	self assert: self deadLetterCount equals: 1
]

{ #category : #tests }
SoilQueueRemoveLaneTest >> testTheDefaultLaneStays [

	| queue |
	queue := self queue.
	self should: [ queue removeLane: #default ] raise: Error.
	self assert: self laneNamesOnDisk equals: #( #default #b )
]

{ #category : #helpers }
SoilQueueRemoveLaneTest >> workspaceIn: aTransaction [

	^ aTransaction root at: #queue
]
