"
What the wrapper has to hold up before anything is built on it: the state machine
refuses the transitions that would hide a crash, what holds after an abort is the
subclass's to say, and an entry read back from disk leaves a cluster-root target where it
is instead of materializing it.

The last one is the reason the wrapper exists in this shape, and it is the one that
cannot be seen in memory -- it needs a real database and a second transaction.
"
Class {
	#name : #SoilQueueEntryTest,
	#superclass : #TestCase,
	#instVars : [
		'soil'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #accessing }
SoilQueueEntryTest >> path [

	^ 'soil-queue-tests'
]

{ #category : #running }
SoilQueueEntryTest >> setUp [

	super setUp.
	soil := Soil path: self path.
	soil
		destroy;
		initializeFilesystem
]

{ #category : #running }
SoilQueueEntryTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueEntryTest >> testAClaimCanBeReleasedBackToPending [
	"how an orphaned claim gets back into circulation"

	| entry |
	entry := SoilQueueTestEntry on: 'work'.
	entry claimAt: DateAndTime now.
	entry releaseClaim.
	self assert: entry isPending.
	self assert: entry claimedAt isNil
]

{ #category : #tests }
SoilQueueEntryTest >> testAClusterRootTargetIsNotMaterializedWithMe [
	"the property the whole shape of the wrapper rests on: selection and diagnosis read an
	entry without dragging the target's object graph along. It holds only because the
	target is a cluster root of its own -- see #testAPlainTargetIsMaterializedWithMe for
	what happens when it is not"

	| txn readBack |
	txn := soil newTransaction.
	txn root: (SoilQueueTestEntry on: SOTestClusterAlwaysRoot new).
	txn commit.

	txn := soil newTransaction.
	readBack := txn root.
	self
		assert: (readBack instVarNamed: 'target') class
		equals: SoilObjectProxy.
	txn abort
]

{ #category : #tests }
SoilQueueEntryTest >> testAPlainTargetIsMaterializedWithMe [
	"the counterpart, and the reason the first user had to make its domain object a cluster
	root: Object>>#soilClusterRootIn: is empty, so an ordinary reference belongs to my
	cluster and comes back in full"

	| txn readBack |
	txn := soil newTransaction.
	txn root: (SoilQueueTestEntry on: (OrderedCollection with: 'payload')).
	txn commit.

	txn := soil newTransaction.
	readBack := txn root.
	self
		assert: (readBack instVarNamed: 'target')
		equals: (OrderedCollection with: 'payload').
	txn abort
]

{ #category : #tests }
SoilQueueEntryTest >> testAStepThatGoesThroughSetsTheCountBack [
	"it counts the times in a row I was given back, and a step that went through ends the
	row"

	| entry |
	entry := SoilQueueTestEntry on: 'work'.
	entry
		noteOrphaned;
		noteOrphaned;
		noteStepDone.
	self assert: entry orphanedRetries equals: 0
]

{ #category : #tests }
SoilQueueEntryTest >> testAnEntryStartsPendingAndUnclaimed [

	| entry |
	entry := SoilQueueTestEntry on: 'work'.
	self assert: entry isPending.
	self assert: entry claimedAt isNil
]

{ #category : #tests }
SoilQueueEntryTest >> testClaimingRecordsTheTime [

	| entry now |
	now := DateAndTime now.
	entry := SoilQueueTestEntry on: 'work'.
	entry claimAt: now.
	self assert: entry isClaimed.
	self assert: entry claimedAt equals: now
]

{ #category : #tests }
SoilQueueEntryTest >> testClaimingTwiceIsRefused [
	"a second claim on the same entry means two workers hold it. Doing nothing quietly is
	what would make that invisible"

	| entry |
	entry := SoilQueueTestEntry on: 'work'.
	entry claimAt: DateAndTime now.
	self
		should: [ entry claimAt: DateAndTime now ]
		raise: SoilQueueWrongEntryState
]

{ #category : #tests }
SoilQueueEntryTest >> testCompensationIsTheSubclassesToImplement [

	| target entry |
	target := SoilQueueTestTarget new.
	target addEffect: #ran.
	entry := SoilQueueTestCompensatingEntry on: target.
	entry resumeAfterAbortIn: nil.
	self assert: target effects equals: #(  ).
	self assert: target compensations equals: #( 1 )
]

{ #category : #tests }
SoilQueueEntryTest >> testDeadLetteringDropsTheClaim [
	"dead lettering parks an entry visibly instead of deleting it, and it is no longer
	held by anyone"

	| entry |
	entry := SoilQueueTestEntry on: 'work'.
	entry claimAt: DateAndTime now.
	entry markDeadLetter.
	self assert: entry isDeadLetter.
	self assert: entry claimedAt isNil
]

{ #category : #tests }
SoilQueueEntryTest >> testFinishingAnUnclaimedEntryIsRefused [
	"work that nobody took cannot be finished"

	self
		should: [ (SoilQueueTestEntry on: 'work') markDone ]
		raise: SoilQueueWrongEntryState
]

{ #category : #tests }
SoilQueueEntryTest >> testTheAbstractEntryHasNoAnswerAfterAnAbort [
	"no default: each of the three answers demands something different of the subclass,
	and a default -- an empty method above all -- would hand out one of them silently"

	self
		should: [ SoilQueueEntry new resumeAfterAbortIn: nil ]
		raise: SubclassResponsibility
]

{ #category : #tests }
SoilQueueEntryTest >> testWorkingRunsTheSubclassesUnit [

	| entry |
	entry := SoilQueueTestEntry on: 'work'.
	self assert: (entry performIn: nil) equals: #finished.
	self assert: entry runCount equals: 1
]
