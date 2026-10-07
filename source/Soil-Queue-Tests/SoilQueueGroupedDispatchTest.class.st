"
How a grouped lane hands out: of each group only the first entry, and only while no
other entry of that group is out. A worker carries on with its own group when it can;
otherwise the groups take turns, from behind the one handed out last.

The keys themselves are SoilQueueGroupedLaneTest's.
"
Class {
	#name : #SoilQueueGroupedDispatchTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueGroupedDispatchTest >> assign: aQueue [

	^ self assign: aQueue preferring: nil
]

{ #category : #helpers }
SoilQueueGroupedDispatchTest >> assign: aQueue preferring: aKey [

	^ aQueue assignNextIn: (aQueue lane: #groups) preferring: aKey
]

{ #category : #helpers }
SoilQueueGroupedDispatchTest >> finish: aKey in: aQueue [
	"what a worker does with an entry that is done: out of the ordering, then no longer out"

	self inTransaction: [ :txn | (self workspaceIn: txn) removeKey: aKey ].
	aQueue release: aKey
]

{ #category : #helpers }
SoilQueueGroupedDispatchTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #accessing }
SoilQueueGroupedDispatchTest >> path [

	^ 'soil-queue-grouped-dispatch-tests'
]

{ #category : #helpers }
SoilQueueGroupedDispatchTest >> put: anInteger into: aGroup [
	"anInteger entries of one group, due now, and answer their keys in the order they went in"

	^ self put: anInteger into: aGroup dueAt: clock now
]

{ #category : #helpers }
SoilQueueGroupedDispatchTest >> put: anInteger into: aGroup dueAt: aDateAndTime [

	^ self inTransaction: [ :txn |
		| workspace |
		workspace := self workspaceIn: txn.
		(1 to: anInteger) collect: [ :each |
			workspace
				add: ((SoilQueueTestEntry on: 'work')
					groupId: aGroup;
					readyAt: aDateAndTime;
					yourself)
				to: (workspace laneNamed: #groups) ] ]
]

{ #category : #helpers }
SoilQueueGroupedDispatchTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ | queue |
	  queue := SoilQueueTestUnforkedQueue from: ((SoilQueue onWorkspace: (self workspaceIn: txn) in: txn)
		clock: clock;
		yourself).
	  (queue pool: #default) size: 10.
	  queue ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueGroupedDispatchTest >> setUp [

	super setUp.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 9 day: 28 hour: 12 minute: 0 second: 0 offset: Duration zero).
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
		workspace initializeIn: txn.
		workspace addLaneNamed: #groups format: SoilQueueGroupedKeyFormat new ]
]

{ #category : #running }
SoilQueueGroupedDispatchTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueGroupedDispatchTest >> testAClaimedFirstEntryHoldsUpItsGroup [
	"claimed and held by nobody is what a crash leaves behind. Until the recovery pass has
	dealt with it, the step after it must wait"

	| keys queue |
	keys := self put: 2 into: 7.
	queue := self queue.
	queue claim: keys first.
	self assert: (self assign: queue) equals: nil
]

{ #category : #tests }
SoilQueueGroupedDispatchTest >> testAFirstEntryThatIsNotDueHoldsUpItsGroupOnly [
	"a later entry of the same group is due and still waits; another group goes. And the
	time the waiting one falls due is what the queue wakes for"

	| late other queue |
	late := self put: 1 into: 7 dueAt: clock now + 1 hour.
	self put: 1 into: 7.
	other := self put: 1 into: 8.
	queue := self queue.
	self assert: (self assign: queue) equals: other first.
	self assert: (self assign: queue) equals: nil.
	self assert: queue wakeAt equals: clock now + 1 hour
]

{ #category : #tests }
SoilQueueGroupedDispatchTest >> testAWorkerCarriesOnWithItsOwnGroup [
	"after its step, the worker takes the next step of its chain rather than the next group
	in turn"

	| seven queue first |
	seven := self put: 2 into: 7.
	self put: 1 into: 8.
	queue := self queue.
	first := self assign: queue.
	self assert: first equals: seven first.
	self finish: first in: queue.
	self assert: (self assign: queue preferring: first) equals: seven second
]

{ #category : #tests }
SoilQueueGroupedDispatchTest >> testAWorkerRunsItsChainInOrder [
	"the whole way: the dispatcher starts one worker for the one group, and the worker works
	the group off step by step, in the order the steps went in"

	| keys queue worker ran key |
	keys := self put: 3 into: 7.
	queue := self queue.
	queue runStep.
	self assert: queue started size equals: 1.
	worker := queue started first.
	ran := OrderedCollection new.
	[ (key := worker runOnce) notNil ] whileTrue: [ ran add: key ].
	self assert: ran asArray equals: keys asArray
]

{ #category : #tests }
SoilQueueGroupedDispatchTest >> testAnotherGroupGoesOutWhileOneIsOut [

	| seven eight queue |
	seven := self put: 2 into: 7.
	eight := self put: 1 into: 8.
	queue := self queue.
	self assert: (self assign: queue) equals: seven first.
	self assert: (self assign: queue) equals: eight first.
	self assert: (self assign: queue) equals: nil
]

{ #category : #tests }
SoilQueueGroupedDispatchTest >> testGroupsTakeTurns [
	"without a chain to carry on with, the next group behind the one handed out last goes,
	round the end and back to the front -- so that low group ids do not always win"

	| one two three queue |
	one := self put: 2 into: 1.
	two := self put: 2 into: 2.
	three := self put: 2 into: 3.
	queue := self queue.
	{ one. two. three. one } do: [ :group |
		| key |
		key := self assign: queue.
		self assert: key equals: group first.
		queue release: key ]
]

{ #category : #tests }
SoilQueueGroupedDispatchTest >> testOnlyTheFirstEntryOfAGroupGoesOut [

	| keys queue |
	keys := self put: 3 into: 7.
	queue := self queue.
	self assert: (self assign: queue) equals: keys first.
	self assert: (self assign: queue) equals: nil
]

{ #category : #tests }
SoilQueueGroupedDispatchTest >> testTheDispatcherStartsAWorkerPerGroupWithSomethingDue [
	"one per group that can go -- the number of entries behind a first one does not ask for
	more workers, and a group whose first entry is not due asks for none"

	| queue |
	self put: 3 into: 1.
	self put: 1 into: 2.
	self put: 1 into: 3 dueAt: clock now + 1 hour.
	queue := self queue.
	queue runStep.
	self assert: queue started size equals: 2
]

{ #category : #tests }
SoilQueueGroupedDispatchTest >> testTheNextEntryOfAGroupGoesOutWhenTheFirstIsDone [

	| keys queue |
	keys := self put: 2 into: 7.
	queue := self queue.
	self finish: (self assign: queue) in: queue.
	self assert: (self assign: queue) equals: keys second
]

{ #category : #helpers }
SoilQueueGroupedDispatchTest >> workspaceIn: aTransaction [

	^ aTransaction root at: #queue
]
