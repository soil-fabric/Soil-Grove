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
	self queue claim: (self currentKeyOf: aKey)
]

{ #category : #helpers }
SoilQueueCrashTest >> crashBeforeTheNextStepOn: aKey [
	"the simpler case: the entry was taken and the image went away before it did anything"

	self queue claim: (self currentKeyOf: aKey)
]

{ #category : #helpers }
SoilQueueCrashTest >> currentKeyOf: aKey [
	"the key the entry that was put in under aKey lies under now. An entry that is given back
	waits first, and its key moves with the time it waits for -- what stays is its id"

	| id txn |
	id := self idOf: aKey.
	txn := soil newTransaction.
	^ [ | found |
	  (self workspaceIn: txn) keysAndEntriesDo: [ :key :entry |
		entry id = id ifTrue: [ found := key ] ].
	  found ifNil: [ aKey ] ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueCrashTest >> deadLetters [
	"each parked entry as its id, its state and how often it lost its worker"

	| txn letters |
	txn := soil newTransaction.
	letters := OrderedCollection new.
	[ (self workspaceIn: txn) deadLettersDo: [ :key :entry |
		letters add: { entry id. entry state. entry orphanedRetries } ] ]
		ensure: [ txn abort ].
	^ letters asArray
]

{ #category : #helpers }
SoilQueueCrashTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueCrashTest >> entryAt: aKey do: aBlock [
	"an entry comes back as a proxy, so the question has to be asked inside the transaction
	that can still resolve it. Answers nil, without evaluating the block, when the entry is
	no longer in the ordering.

	Found by the id it was put in with, not by aKey: an entry that is given back waits
	first, and its key moves with the time it waits for"

	| txn id |
	id := self idOf: aKey.
	txn := soil newTransaction.
	^ [ | found |
	  (self workspaceIn: txn) keysAndEntriesDo: [ :key :entry |
		entry id = id ifTrue: [ found := entry ] ].
	  found ifNotNil: [ aBlock value: found ] ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueCrashTest >> idOf: aKey [
	"the eight bytes that tell an entry apart, in the key it was put in under: the due time
	comes first, then the id"

	^ (aKey asByteArrayOfSize: 24) copyFrom: 9 to: 16
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

{ #category : #helpers }
SoilQueueCrashTest >> orphanedRetryLimit: anInteger [

	self inTransaction: [ :txn |
		(self descriptionIn: txn) orphanedRetryLimit: anInteger ]
]

{ #category : #accessing }
SoilQueueCrashTest >> path [

	^ 'soil-queue-tests'
]

{ #category : #helpers }
SoilQueueCrashTest >> put: aBlock [
	"aBlock builds the entry on the target read in the same transaction"

	^ self inTransaction: [ :txn |
		(self workspaceIn: txn) add: (aBlock value: (txn root at: #target)) ]
]

{ #category : #helpers }
SoilQueueCrashTest >> queue [
	"a fresh live queue on the same description, configured as a start configures it --
	what comes back after a restart, with nothing in flight and no memory of what was out"

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		configureFrom: (self descriptionIn: txn) in: txn;
		supervisor: soil newResidentSupervisor;
		yourself ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueCrashTest >> retriesOf: aKey [

	^ self entryAt: aKey do: [ :entry |
		{ entry state. entry orphanedRetries. entry failureRetries } ]
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
		"an entry that is given back waits, by the curve of its lane. These tests drive a
		restart and want the entry again at once, so the wait is nothing; the wait itself
		is tested where it is the point"
		(self descriptionIn: txn) backoffBase: 0 seconds.
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
SoilQueueCrashTest >> testAClaimCountsNoRetry [
	"a claim is taken for every attempt, the first one included. Counting there would count
	attempts, and every retry for a failure would show up as a lost worker as well"

	| key |
	key := self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	self crashBeforeTheNextStepOn: key.

	self assert: (self retriesOf: key) equals: #( #claimed 0 0 )
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
	self workOneUnit.
	self workOneUnit.
	self assert: (self entryAt: key do: [ :entry | entry progress ]) equals: 2.
	self assert: self targetEffects equals: #( 1 2 ).

	self crashBeforeTheNextStepOn: key.
	self workOffEverything.

	self assert: (self stateOf: key) equals: nil.
	self assert: self targetEffects equals: #( 1 2 3 )
]

{ #category : #tests }
SoilQueueCrashTest >> testAnEntryThatKeepsLosingItsWorkerIsParked [
	"what takes its worker with it every time -- the poison entry -- stops coming back once
	the limit is used up. It is parked, not released: releasing it would hand the next
	worker the same end"

	| key |
	self orphanedRetryLimit: 2.
	key := self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	2 timesRepeat: [
		self crashBeforeTheNextStepOn: key.
		self queue recoverOrphanedClaims ].
	self assert: (self retriesOf: key) equals: #( #pending 2 0 ).

	self crashBeforeTheNextStepOn: key.
	self queue recoverOrphanedClaims.
	self assert: (self retriesOf: key) isNil.
	self assert: self deadLetters equals: { { self idOf: key. #deadLetter. 2 } }
]

{ #category : #tests }
SoilQueueCrashTest >> testAnOrphanedClaimCountsAsAnOrphanedRetry [
	"the one place where the queue learns that a worker went away is the recovery pass, so
	that is where it is counted -- and only there"

	| key |
	key := self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	self crashBeforeTheNextStepOn: key.
	self queue recoverOrphanedClaims.

	self assert: (self retriesOf: key) equals: #( #pending 1 0 )
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

{ #category : #tests }
SoilQueueCrashTest >> testAnEntryHeldByAWorkerOfTheRunBeforeIsNotTakenAwayAtAStart [
	"asking again at a start is safe for the same reason the first ask is: a restart can come
	while a worker of the run before is still on its entry, and that worker holds it"

	| key queue txn |
	key := self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	queue := self queue.
	queue recoverOrphanedClaims.
	txn := soil newTransaction.
	queue assignNextDueAt: DateAndTime now in: txn ifNone: [ nil ].
	txn abort.
	queue claim: key.
	txn := soil newTransaction.
	[ queue prepareIn: txn ] ensure: [ txn abort ].
	queue recoverOrphanedClaims.
	self assert: (self stateOf: key) equals: #claimed
]

{ #category : #tests }
SoilQueueCrashTest >> testAnOrphanThatCannotBeGivenBackDoesNotKeepTheOthers [
	"the cleanup of the first one throws. The pass goes on to the second, and what failed is
	reported like a failed step and stays claimed, for the next start to try again"

	| failing healthy queue |
	failing := self put: [ :target |
		(SoilQueueTestUncompensableEntry on: target)
			readyAt: DateAndTime now - 2 hours;
			yourself ].
	healthy := self put: [ :target |
		(SoilQueueTestRepeatingEntry on: target)
			readyAt: DateAndTime now - 1 hour;
			yourself ].
	self crashBeforeTheNextStepOn: failing.
	self crashBeforeTheNextStepOn: healthy.
	queue := self queue.
	queue recoverOrphanedClaims.
	self assert: (self stateOf: healthy) equals: #pending.
	self assert: (self stateOf: failing) equals: #claimed.
	self assert: queue stepErrorCount equals: 1.
	self assert: queue lastStepError messageText equals: 'the cleanup cannot be done'
]

{ #category : #tests }
SoilQueueCrashTest >> testAQueueThatStartsAgainGivesBackWhatTheRunBeforeLeft [
	"a restart runs on the same instance. The question that was asked once per instance was
	never asked again, so a worker that was taken away in the stop left its claim behind and
	nothing found it before the image started anew"

	| key queue txn |
	key := self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	queue := self queue.
	queue recoverOrphanedClaims.
	queue claim: key.
	queue recoverOrphanedClaims.
	self assert: (self stateOf: key) equals: #claimed.
	txn := soil newTransaction.
	[ queue prepareIn: txn ] ensure: [ txn abort ].
	queue recoverOrphanedClaims.
	self assert: (self retriesOf: key) equals: #( #pending 1 0 )
]

{ #category : #tests }
SoilQueueCrashTest >> testWithoutALimitAnOrphanAlwaysComesBack [
	"no limit is the default: how many lost workers are too many is the embedder's
	knowledge, and a number here would be a guess"

	| key |
	key := self put: [ :target | SoilQueueTestRepeatingEntry on: target ].
	5 timesRepeat: [
		self crashBeforeTheNextStepOn: key.
		self queue recoverOrphanedClaims ].

	self assert: (self retriesOf: key) equals: #( #pending 5 0 )
]

{ #category : #helpers }
SoilQueueCrashTest >> workOffEverything [
	"what a restarted queue does, in the order it does it: the dispatcher gives orphaned
	claims back first, and only then is there anything for a worker to take. Driven
	straight through rather than forked -- a test that waits for a process cannot say what
	happened in it"

	| queue |
	queue := self queue.
	queue recoverOrphanedClaims.
	(SoilQueueWorker on: queue) run.
	^ queue
]

{ #category : #helpers }
SoilQueueCrashTest >> workOneUnit [
	"exactly one entry, so a test can look in between"

	^ (SoilQueueWorker on: self queue) runOnce
]

{ #category : #helpers }
SoilQueueCrashTest >> workspaceIn: aTransaction [
	"where the entries are: the workspace the description holds"

	^ (self descriptionIn: aTransaction) workspace
]
