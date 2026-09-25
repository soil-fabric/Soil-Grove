"
The description configures each lane: what is set for a lane holds for it, what is not
comes from the values set for all lanes, and those from the defaults.

The same for the worker pools. A lane draws on the pool named for it, lanes named for one
pool share it, and a lane named for none draws on #default, the pool of the worker limit.

On a workspace with markers and a second lane, #b, registered as the resident #work.
"
Class {
	#name : #SoilQueueLaneSettingsTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueLaneSettingsTest >> configure: aBlock [

	self inTransaction: [ :txn | aBlock value: (self descriptionIn: txn) ]
]

{ #category : #helpers }
SoilQueueLaneSettingsTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueLaneSettingsTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueLaneSettingsTest >> leftIn: aSymbol [

	| txn count |
	txn := soil newTransaction.
	count := 0.
	[ | workspace |
	  workspace := self workspaceIn: txn.
	  workspace keysAndEntriesIn: (workspace laneNamed: aSymbol) do: [ :key :entry | count := count + 1 ] ]
		ensure: [ txn abort ].
	^ count
]

{ #category : #accessing }
SoilQueueLaneSettingsTest >> path [

	^ 'soil-queue-lane-settings-tests'
]

{ #category : #helpers }
SoilQueueLaneSettingsTest >> put: anInteger into: aSymbol [

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
SoilQueueLaneSettingsTest >> queue [
	"a live queue made by its description, the way a supervisor would make one"

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		supervisor: soil newResidentSupervisor;
		clock: clock;
		yourself ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueLaneSettingsTest >> setUp [

	| workspace |
	super setUp.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 9 day: 25 hour: 12 minute: 0 second: 0 offset: Duration zero).
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot.
	workspace := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24 markerWidth: 1.
	workspace addLaneNamed: #b format: SoilQueueTimeOrderedKeyFormat new.
	workspace addLaneNamed: #c format: SoilQueueTimeOrderedKeyFormat new.
	soil addResidentDescription: (SoilQueueDescription named: #work workspace: workspace)
]

{ #category : #running }
SoilQueueLaneSettingsTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueLaneSettingsTest >> testALaneRunsAtItsOwnRate [

	| queue |
	self configure: [ :description | description rateLimit: 1 per: 1 minute forLane: #b ].
	self put: 3 into: #default.
	self put: 3 into: #b.
	queue := self queue.
	(SoilQueueWorker on: queue lane: (queue lane: #default)) run.
	(SoilQueueWorker on: queue lane: (queue lane: #b)) run.

	self assert: (self leftIn: #default) equals: 0.
	self assert: (self leftIn: #b) equals: 2
]

{ #category : #tests }
SoilQueueLaneSettingsTest >> testALaneSettingIsCheckedWhenItIsSet [
	"not at the next start, where it would stop the resident from coming up"

	self configure: [ :description |
		self should: [ description rateLimit: 0 per: 1 minute forLane: #b ] raise: Error.
		self should: [ description failureRetryLimit: -1 forLane: #b ] raise: Error.
		self should: [ description orphanedRetryLimit: -1 forLane: #b ] raise: Error.
		self should: [ description workerPool: #b size: 0 ] raise: Error ]
]

{ #category : #tests }
SoilQueueLaneSettingsTest >> testAnUnsizedPoolHasOnePlace [
	"the cautious direction, as for the worker limit"

	| queue |
	self configure: [ :description | description workerPool: #slow forLane: #b ].
	queue := self queue.
	self assert: (queue lane: #b) pool name equals: #slow.
	self assert: (queue lane: #b) pool size equals: 1
]

{ #category : #tests }
SoilQueueLaneSettingsTest >> testLanesNamedForOnePoolShareIt [

	| queue |
	self configure: [ :description |
		description
			workerLimit: 3;
			workerPool: #side size: 2;
			workerPool: #side forLane: #b;
			workerPool: #side forLane: #c ].
	queue := self queue.

	self assert: (queue lane: #b) pool identicalTo: (queue lane: #c) pool.
	self assert: (queue lane: #b) pool size equals: 2.
	self assert: (queue lane: #default) pool name equals: #default.
	self assert: (queue lane: #default) pool size equals: 3
]

{ #category : #tests }
SoilQueueLaneSettingsTest >> testWhatIsNotSetForALaneComesFromAllLanes [

	| queue |
	self configure: [ :description |
		description
			failureRetryLimit: 5;
			backoffBase: 2 seconds;
			backoffBase: 10 seconds forLane: #b ].
	queue := self queue.

	self assert: (queue lane: #b) failureRetryLimit equals: 5.
	self assert: (queue lane: #b) backoffBase equals: 10 seconds.
	self assert: (queue lane: #c) backoffBase equals: 2 seconds.
	self assert: (queue lane: #b) backoffCap equals: 1 hour
]

{ #category : #tests }
SoilQueueLaneSettingsTest >> testWithoutAPoolNamedALaneSharesTheDefault [

	| queue |
	queue := self queue.
	self assert: (queue lane: #b) pool identicalTo: (queue lane: #default) pool.
	self assert: queue pools size equals: 1
]

{ #category : #helpers }
SoilQueueLaneSettingsTest >> workspaceIn: aTransaction [

	^ (self descriptionIn: aTransaction) workspace
]
