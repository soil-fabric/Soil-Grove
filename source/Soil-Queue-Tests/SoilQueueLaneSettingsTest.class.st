"
The description configures each lane: what is set for a lane holds for it, what is not
comes from the values set for all lanes, and those from the defaults.

The same for the worker limit. A lane has the one set for it, or the one set for all
lanes, and one place if neither is set; lanes share no places.

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

{ #category : #accessing }
SoilQueueLaneSettingsTest >> path [

	^ 'soil-queue-lane-settings-tests'
]

{ #category : #helpers }
SoilQueueLaneSettingsTest >> queue [
	"a live queue made by its description, the way a supervisor would make one, and
	configured the way a start configures it"

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		configureFrom: (self descriptionIn: txn) in: txn;
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
SoilQueueLaneSettingsTest >> testALaneSettingIsCheckedWhenItIsSet [
	"not at the next start, where it would stop the resident from coming up"

	self configure: [ :description |
		self should: [ description failureRetryLimit: -1 forLane: #b ] raise: Error.
		self should: [ description orphanedRetryLimit: -1 forLane: #b ] raise: Error.
		self should: [ description workerLimit: 0 forLane: #b ] raise: Error ]
]

{ #category : #tests }
SoilQueueLaneSettingsTest >> testALaneTakesItsOwnWorkerLimit [

	| queue |
	self configure: [ :description |
		description
			workerLimit: 3;
			workerLimit: 2 forLane: #b ].
	queue := self queue.

	self assert: (queue lane: #b) workerLimit equals: 2.
	self assert: (queue lane: #c) workerLimit equals: 3.
	self assert: (queue lane: #default) workerLimit equals: 3
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
SoilQueueLaneSettingsTest >> testWithoutALimitSetALaneHasOnePlace [
	"the cautious direction, as for the worker limit of all lanes"

	| queue |
	queue := self queue.
	self assert: (queue lane: #b) workerLimit equals: 1.
	self assert: (queue lane: #default) workerLimit equals: 1
]
