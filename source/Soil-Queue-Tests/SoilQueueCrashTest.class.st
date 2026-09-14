"
The acceptance criterion of the core: an entry survives a crash the way its own
resumption semantics say it should, and one test for each of the three.

A crash is simulated as it actually looks in the database afterwards -- an entry that
says claimed, with no live queue holding it. Committing the claim before the work is what
makes that visible at all: without it, an entry that died mid-work would look exactly
like one that never started.

Two of the three crash *after* the effect and before the note that it happened, because
that is the case the semantics are for. Nothing in the database tells that apart from a
crash before the effect, which is why the answer has to come from the entry: the
repeating one runs again and the effect happens twice, the compensating one is cleaned up
first and it does not. The continuing one crashes before its next step, where what
matters is that the steps already done are not done again.

The effects are counted on the target, not on the entry: a finished entry leaves the
ordering and nothing refers to it any more, while what the work did to the world stays.
"
Class {
	#name : #SoilQueueCrashTest,
	#superclass : #TestCase,
	#instVars : [
		'soil'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueCrashTest >> crashAfterAnEffectOn: aKey [
	"the hard case: the effect on the outside happened and the commit that would have noted
	it never came. All that is left is the claim"

	self inTransaction: [ :txn | (txn root at: #target) addEffect: #interrupted ].
	self queue claim: aKey
]

{ #category : #helpers }
SoilQueueCrashTest >> crashBeforeTheNextStepOn: aKey [
	"the simpler case: the entry was taken and the image went away before it did anything"

	self queue claim: aKey
]

{ #category : #helpers }
SoilQueueCrashTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueCrashTest >> entryAt: aKey do: aBlock [
	"an entry comes back as a proxy, so the question has to be asked inside the transaction
	that can still resolve it. Answers nil, without evaluating the block, when the entry is
	no longer in the ordering."

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) entryAt: aKey ifAbsent: [ nil ])
		ifNotNil: [ :entry | aBlock value: entry ] ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueCrashTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #accessing }
SoilQueueCrashTest >> path [

	^ 'soil-queue-tests'
]

{ #category : #helpers }
SoilQueueCrashTest >> put: aBlock [
	"aBlock builds the entry on the target read in the same transaction"

	^ self inTransaction: [ :txn |
		(self descriptionIn: txn) add: (aBlock value: (txn root at: #target)) ]
]

{ #category : #helpers }
SoilQueueCrashTest >> queue [
	"a fresh live queue on the same description -- what comes back after a restart, with
	nothing in flight and no memory of what was out"

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		supervisor: soil newResidentSupervisor;
		yourself ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueCrashTest >> setUp [

	super setUp.
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot.
	soil addResidentDescription: (SoilQueueDescription
		named: #work
		timeOrderedWithBackend: SoilSkipList
		keySize: 24).
	self inTransaction: [ :txn |
		txn root at: #target put: SoilQueueTestTarget new ]
]

{ #category : #helpers }
SoilQueueCrashTest >> stateOf: aKey [
	"nil when the entry has left the ordering"

	^ self entryAt: aKey do: [ :entry | entry state ]
]

{ #category : #helpers }
SoilQueueCrashTest >> targetCompensations [

	| txn |
	txn := soil newTransaction.
	^ [ (txn root at: #target) compensations ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueCrashTest >> targetEffects [

	| txn |
	txn := soil newTransaction.
	^ [ (txn root at: #target) effects ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueCrashTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueCrashTest >> testACompensatingEntryIsCleanedUpBeforeItRunsAgain [
	"the case that gets forgotten, and the one the other two cannot cover: the aborted
	attempt left an effect standing, so the cleanup goes first and takes it away. What is
	left afterwards is one effect, not two -- and the cleanup found exactly the one that
	was there"

	| key |
	key := self put: [ :target | SoilQueueTestCompensatingEntry on: target ].
	self crashAfterAnEffectOn: key.
	self assert: self targetEffects equals: #( #interrupted ).

	self workOffEverything.
	self assert: (self stateOf: key) equals: nil.
	self assert: self targetCompensations equals: #( 1 ).
	self assert: self targetEffects equals: #( #ran )
]

{ #category : #tests }
SoilQueueCrashTest >> testAContinuingEntryPicksUpWhereItStopped [
	"the steps already done are not done again, because the progress was committed after
	each of them"

	| key |
	key := self put: [ :target | SoilQueueTestContinuingEntry on: target steps: 3 ].
	self queue runStep.
	self queue runStep.
	self assert: (self entryAt: key do: [ :entry | entry progress ]) equals: 2.
	self assert: self targetEffects equals: #( 1 2 ).

	self crashBeforeTheNextStepOn: key.
	self workOffEverything.

	self assert: (self stateOf: key) equals: nil.
	self assert: self targetEffects equals: #( 1 2 3 )
]

{ #category : #tests }
SoilQueueCrashTest >> testARepeatingEntryRunsAgainAndTheEffectHappensTwice [
	"at least once, not exactly once. It made no note of how far it got and needs none --
	what makes the repetition harmless is the receiver, and that is a promise the entry
	gives by calling itself repeating"

	| key |
	key := self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	self crashAfterAnEffectOn: key.

	self workOffEverything.
	self assert: (self stateOf: key) equals: nil.
	self assert: self targetEffects equals: #( #interrupted #ran ).
	self assert: self targetCompensations equals: #(  )
]

{ #category : #tests }
SoilQueueCrashTest >> testAnEntryHeldByALiveWorkerIsNotTakenAway [
	"the recovery reads exactly the state a running worker leaves behind. Only the live
	queue can tell the two apart, and that is what its set of keys is for"

	| key queue txn |
	key := self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	queue := self queue.
	txn := soil newTransaction.
	queue assignNextDueAt: DateAndTime now in: txn ifNone: [ nil ].
	txn abort.
	queue claim: key.

	queue recoverOrphanedClaims.
	self assert: (self stateOf: key) equals: #claimed
]

{ #category : #tests }
SoilQueueCrashTest >> testAnOrphanedClaimIsFoundAndGivenBack [
	"found over the entries and not over the index: a claim does not change a key, so the
	ordering cannot tell a claimed entry from a pending one"

	| key |
	key := self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	self crashBeforeTheNextStepOn: key.
	self assert: (self stateOf: key) equals: #claimed.

	self queue recoverOrphanedClaims.
	self assert: (self stateOf: key) equals: #pending.
	self assert: (self entryAt: key do: [ :entry | entry claimedAt ]) isNil
]

{ #category : #helpers }
SoilQueueCrashTest >> workOffEverything [
	"a restarted queue, driven until nothing is due any more"

	| queue |
	queue := self queue.
	5 timesRepeat: [ queue runStep ].
	^ queue
]
