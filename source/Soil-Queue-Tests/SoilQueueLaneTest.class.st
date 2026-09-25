"
A lane holds its values; nobody reads the configuration for it once the queue runs.

With a resident, the values come from the description when the queue is created and at
every start -- a setting changed on the description is configuration for the next start.
Without one, the queue is created on its workspace and whoever does that sets the values
on the lane in code.

Driven on a clock that stands still until it is moved.
"
Class {
	#name : #SoilQueueLaneTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueLaneTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueLaneTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueLaneTest >> left: aWorkspaceBlock [
	"how many entries are still in the ordering of the workspace aWorkspaceBlock finds"

	| txn count |
	txn := soil newTransaction.
	count := 0.
	[ (aWorkspaceBlock value: txn) keysAndEntriesDo: [ :key :entry | count := count + 1 ] ]
		ensure: [ txn abort ].
	^ count
]

{ #category : #accessing }
SoilQueueLaneTest >> path [

	^ 'soil-queue-lane-tests'
]

{ #category : #helpers }
SoilQueueLaneTest >> put: anInteger into: aWorkspaceBlock [

	self inTransaction: [ :txn |
		anInteger timesRepeat: [
			(aWorkspaceBlock value: txn) add: ((SoilQueueTestEntry on: 'work')
				eligibleAt: clock now;
				yourself) ] ]
]

{ #category : #helpers }
SoilQueueLaneTest >> residentQueue [
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
SoilQueueLaneTest >> setUp [

	super setUp.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 9 day: 24 hour: 12 minute: 0 second: 0 offset: Duration zero).
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot
]

{ #category : #running }
SoilQueueLaneTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueLaneTest >> testAChangedRateHoldsFromTheNextStart [
	"the lane took its values when the queue was made. A rate written on the description
	afterwards is the configuration of the next start -- a restart of the resident is how it
	takes effect, the way it is for every resident"

	| queue workspace txn |
	soil addResidentDescription: (SoilQueueDescription
		named: #work
		timeOrderedWithBackend: SoilSkipList
		keySize: 24).
	workspace := [ :aTransaction | (self descriptionIn: aTransaction) workspace ].
	queue := self residentQueue.
	self inTransaction: [ :t | (self descriptionIn: t) rateLimit: 1 per: 1 minute ].
	self put: 3 into: workspace.
	(SoilQueueWorker on: queue) run.
	self assert: (self left: workspace) equals: 0.

	txn := soil newTransaction.
	[ queue prepareIn: txn ] ensure: [ txn abort ].
	self put: 3 into: workspace.
	(SoilQueueWorker on: queue) run.
	self assert: (self left: workspace) equals: 2
]

{ #category : #tests }
SoilQueueLaneTest >> testAQueueRunsOnItsWorkspaceWithoutAResident [
	"load the workspace, create a queue on it, and it works -- no description, no registry,
	nothing that has to be started"

	| workspace queue txn |
	self inTransaction: [ :t |
		| created |
		created := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24.
		t root at: #queue put: created.
		t makeRoot: created.
		created initializeIn: t ].
	workspace := [ :aTransaction | aTransaction root at: #queue ].
	txn := soil newTransaction.
	[ queue := (SoilQueue onWorkspace: (workspace value: txn) in: txn)
		clock: clock;
		yourself ] ensure: [ txn abort ].

	self put: 3 into: workspace.
	(SoilQueueWorker on: queue) run.
	self assert: (self left: workspace) equals: 0
]

{ #category : #tests }
SoilQueueLaneTest >> testWithoutAResidentTheValuesAreSetOnTheLane [
	"no description to read them from, so whoever creates the queue sets them"

	| workspace queue txn |
	self inTransaction: [ :t |
		| created |
		created := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24.
		t root at: #queue put: created.
		t makeRoot: created.
		created initializeIn: t ].
	workspace := [ :aTransaction | aTransaction root at: #queue ].
	txn := soil newTransaction.
	[ queue := (SoilQueue onWorkspace: (workspace value: txn) in: txn)
		clock: clock;
		yourself ] ensure: [ txn abort ].
	(queue lane: #default) rateLimit: 1 per: 1 minute.

	self put: 3 into: workspace.
	(SoilQueueWorker on: queue) run.
	self assert: (self left: workspace) equals: 2
]
