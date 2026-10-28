"
What happens to an entry whose step fails. Two ways, told apart by where the error comes
from.

An error out of the work unit that is not Soil's is a statement about the work. The
throwing transaction is gone, the queue books it in a transaction of its own, and the
entry gives up: a result, not a dead letter -- the target learns of it through
#giveUp:in:, and the entry is done. Nothing is tried again.

Anything else -- an error of Soil's out of the work unit, a commit that does not go
through, a conflict that does not resolve -- leaves the entry claimed with no worker
holding it, and it goes back the way an orphan goes back: counted, after a wait by the
curve of its lane, parked at the lane's limit.

Driven on a clock that stands still until it is moved, so that a backoff is a statement
about time rather than a wait.
"
Class {
	#name : #SoilQueueRetryTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'clock'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueRetryTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #queue
]

{ #category : #helpers }
SoilQueueRetryTest >> due: anEntry [
	"due now by the test's clock"

	^ anEntry
		readyAt: clock now;
		yourself
]

{ #category : #helpers }
SoilQueueRetryTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueRetryTest >> loseTheWorkerOn: aQueue [
	"what a commit that did not go through leaves behind, handed to the queue the way a
	worker hands it: the one entry claimed, and the step failed around its work unit"

	| key |
	key := self onlyKey.
	aQueue claim: key.
	aQueue stepFailed: (Error new messageText: 'the commit failed'; yourself) on: key
]

{ #category : #helpers }
SoilQueueRetryTest >> onlyEntry [
	"state, due time and how often in a row it was given back, of the one entry in the
	ordering, or nil when it has left it. Read inside the transaction, because an entry
	comes back as a proxy"

	| txn |
	txn := soil newTransaction.
	^ [ | found |
	  (self workspaceIn: txn) keysAndEntriesDo: [ :key :entry |
		found := { entry state. entry readyAt. entry orphanedRetries } ].
	  found ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueRetryTest >> onlyKey [
	"the key of the one entry in the ordering. It moves each time the entry is put off"

	| txn |
	txn := soil newTransaction.
	^ [ | found |
	  (self workspaceIn: txn) keysAndEntriesDo: [ :key :entry | found := key ].
	  found ]
		ensure: [ txn abort ]
]

{ #category : #accessing }
SoilQueueRetryTest >> path [

	^ 'soil-queue-retry-tests'
]

{ #category : #helpers }
SoilQueueRetryTest >> put: aBlock [
	"aBlock builds the entry on the target read in the same transaction"

	^ self inTransaction: [ :txn |
		| workspace |
		workspace := self workspaceIn: txn.
		workspace
			add: (self due: (aBlock value: (txn root at: #target)))
			to: workspace defaultLane ]
]

{ #category : #helpers }
SoilQueueRetryTest >> queue [

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
SoilQueueRetryTest >> setUp [

	super setUp.
	clock := SoilQueueTestClock at: (DateAndTime year: 2026 month: 9 day: 24 hour: 12 minute: 0 second: 0 offset: Duration zero).
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot.
	soil addResidentDescription: (SoilQueueDescription
		timeOrderedWithBackend: SoilSkipList
		keySize: 24).
	self inTransaction: [ :txn |
		txn root at: #target put: SoilQueueTestTarget new ]
]

{ #category : #helpers }
SoilQueueRetryTest >> targetEffects [

	| txn |
	txn := soil newTransaction.
	^ [ (txn root at: #target) effects asArray ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueRetryTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueRetryTest >> testAFailureIsRememberedButCountsAsNoStepError [
	"a handled failure is no crash loop, and the step error count is what shows one. The
	error itself stays readable for diagnosis"

	| queue |
	self put: [ :target | SoilQueueTestBrokenEntry on: target ].
	queue := self queue.
	(SoilQueueWorker on: queue) runOnce.

	self assert: queue lastStepError messageText equals: 'the far side refused the request'.
	self assert: queue stepErrorCount equals: 0
]

{ #category : #tests }
SoilQueueRetryTest >> testAFailureAtTheWorkGivesUpAtOnce [
	"nothing is retried that nobody thought through. A retry a far side would want is the
	entry's own business, a due time it sets itself"

	self put: [ :target | SoilQueueTestBrokenEntry on: target ].
	(SoilQueueWorker on: self queue) runOnce.

	self assert: self onlyEntry isNil.
	self
		assert: self targetEffects
		equals: { { #gaveUp. 'the far side refused the request'. 0 } }
]

{ #category : #tests }
SoilQueueRetryTest >> testAnErrorOfSoilsFromTheWorkGivesTheEntryBack [
	"a segment that is not there yet, an index that points nowhere: no statement about the
	work, and often gone a moment later. So the entry is not given up on: it goes back the
	way an orphan goes back, counted, after a wait, and the failed step is counted as one.
	It is not run again at once either -- only a write conflict is"

	| queue |
	self put: [ :target | SoilQueueTestUnreachableEntry on: target ].
	queue := self queue.
	SoilQueueTestUnreachableEntry resetAttempts.
	(SoilQueueWorker on: queue) runOnce.

	self
		assert: self onlyEntry
		equals: { #pending. clock now + 1 second. 1 }.
	self assert: queue stepErrorCount equals: 1.
	self assert: self targetEffects isEmpty.
	self assert: SoilQueueTestUnreachableEntry attempts equals: 1
]

{ #category : #tests }
SoilQueueRetryTest >> testAnErrorOfSoilsSerializerFromTheWorkGivesTheEntryBack [
	"the serializer lies below Soil's core, so what it says is not a SoilError -- and it is
	Soil's all the same: a layout that cannot be migrated is no statement about the work"

	| queue |
	self put: [ :target |
		SoilQueueTestUnreachableEntry on: target raising: SoilLayoutMigrationError ].
	queue := self queue.
	(SoilQueueWorker on: queue) runOnce.

	self
		assert: self onlyEntry
		equals: { #pending. clock now + 1 second. 1 }.
	self assert: self targetEffects isEmpty
]

{ #category : #tests }
SoilQueueRetryTest >> testAnEntryThatCannotBeGivenBackStaysClaimed [
	"giving it back is the queue's business, and when that fails too there is nobody left to
	ask: it stays claimed, both failures are counted, and the next start finds it"

	| key queue |
	key := self put: [ :target | SoilQueueTestUncompensableEntry on: target ].
	queue := self queue.
	queue claim: key.
	queue stepFailed: (Error new messageText: 'the commit failed'; yourself) on: key.
	self assert: self onlyEntry first equals: #claimed.
	self assert: queue stepErrorCount equals: 2.
	self assert: queue lastStepError messageText equals: 'the cleanup cannot be done'
]

{ #category : #tests }
SoilQueueRetryTest >> testAnEntryThatKeepsFailingOutsideItsWorkUnitIsParkedAtTheLimit [
	"the same limit as for a lost worker, because to the queue it is one: a claim that nobody
	finished"

	| queue worker |
	self inTransaction: [ :txn |
		(self descriptionIn: txn) orphanedRetryLimit: 2 ].
	SoilQueueTestConflictingEntry conflictsToRaise: 99.
	self put: [ :target | SoilQueueTestConflictingEntry on: target ].
	queue := self queue.
	worker := SoilQueueWorker on: queue.
	2 timesRepeat: [
		worker runOnce.
		clock advanceBy: 1 hour ].
	self assert: self onlyEntry first equals: #pending.
	worker runOnce.
	self assert: self onlyEntry isNil
]

{ #category : #tests }
SoilQueueRetryTest >> testAnEntryWhoseStepFailsOutsideItsWorkUnitIsGivenBackAndWaits [
	"a work unit that fails at its work is booked. An error of Soil's is not, and an error
	around the work unit is not either: the commit threw, a conflict did not resolve. The
	entry still says claimed and no worker holds it, which is what a lost worker leaves
	behind, so it goes back the way an orphan goes back -- counted as one, and after a
	wait, so that a commit that is not going through right now does not use up the budget
	in milliseconds"

	| queue |
	SoilQueueTestConflictingEntry conflictsToRaise: 99.
	self put: [ :target | SoilQueueTestConflictingEntry on: target ].
	queue := self queue.
	(SoilQueueWorker on: queue) runOnce.
	self
		assert: self onlyEntry
		equals: { #pending. clock now + 1 second. 1 }.
	self assert: queue stepErrorCount equals: 1
]

{ #category : #tests }
SoilQueueRetryTest >> testAStepThatGoesThroughStartsTheWaitOverAgain [
	"the wait doubles with each time in a row an entry is given back. Counted over its life
	instead, a flow instance would wait the full hour after every deploy from the thirteenth
	on, even when the step before had just gone through"

	| queue |
	self put: [ :target | SoilQueueTestContinuingEntry on: target steps: 3 ].
	queue := self queue.
	self loseTheWorkerOn: queue.
	clock advanceBy: 1 second.
	self loseTheWorkerOn: queue.
	clock advanceBy: 2 seconds.
	(SoilQueueWorker on: queue) runOnce.

	self loseTheWorkerOn: queue.
	self
		assert: self onlyEntry
		equals: { #pending. clock now + 1 second. 1 }
]

{ #category : #tests }
SoilQueueRetryTest >> testTheQueueSetsNoCountBackOnItsOwn [
	"#more is the answer of a unit that only put itself off as well -- a throttle that asked
	to wait. Only the entry knows which it was, so a count goes back to nothing when the
	entry says so, and this one never does"

	| queue |
	self put: [ :target | SoilQueueTestPostponingEntry on: target postponedBy: 1 hour ].
	queue := self queue.
	self loseTheWorkerOn: queue.
	clock advanceBy: 1 second.
	(SoilQueueWorker on: queue) runOnce.

	self
		assert: self onlyEntry
		equals: { #pending. clock now + 1 hour. 1 }
]

{ #category : #tests }
SoilQueueRetryTest >> testTheWaitOfAnEntryThatIsGivenBackDoublesWithEachTime [

	| queue worker |
	SoilQueueTestConflictingEntry conflictsToRaise: 99.
	self put: [ :target | SoilQueueTestConflictingEntry on: target ].
	queue := self queue.
	worker := SoilQueueWorker on: queue.
	worker runOnce.
	clock advanceBy: 1 second.
	worker runOnce.
	self
		assert: self onlyEntry
		equals: { #pending. clock now + 2 seconds. 2 }
]

{ #category : #tests }
SoilQueueRetryTest >> testTheBackoffDoublesUpToItsCap [

	| lane |
	lane := SoilQueueLane
		named: #default
		configuredFrom: (SoilQueueDescription new
			backoffBase: 1 second;
			backoffCap: 5 seconds;
			yourself).
	self
		assert: ((1 to: 5) collect: [ :retries | lane retryDelayAfter: retries ]) asArray
		equals: { 1 second. 2 seconds. 4 seconds. 5 seconds. 5 seconds }
]

{ #category : #tests }
SoilQueueRetryTest >> testTheBackoffIsFromOneSecondUpToAnHourByDefault [

	| description |
	description := SoilQueueDescription new.
	self assert: description backoffBase equals: 1 second.
	self assert: description backoffCap equals: 1 hour
]

{ #category : #tests }
SoilQueueRetryTest >> testAFailureAtTheWorkIsSaid [
	"giving up is a result, and nobody is woken for it: the line is what is left of it to
	read, with the error that was the reason"

	| lines |
	self put: [ :target | SoilQueueTestBrokenEntry on: target ].
	(SoilQueueWorker on: self queue) runOnce.

	lines := soil reportedMatching: 'gave up'.
	self assert: lines size equals: 1.
	self assert: (lines first includesSubstring: 'failed at its work (Error: the far side refused the request)').
	self assert: (lines first includesSubstring: 'SoilQueueTestBrokenEntry')
]

{ #category : #tests }
SoilQueueRetryTest >> testAnEntryThatCannotBePrintedIsGivenBackAllTheSame [
	"a target that cannot be read is often why an entry is given back. The line says so
	instead of the entry, and the entry goes back as it would without a line"

	| lines |
	self put: [ :target | SoilQueueTestUnprintableEntry on: target ].
	self loseTheWorkerOn: self queue.

	self
		assert: self onlyEntry
		equals: { #pending. clock now + 1 second. 1 }.
	lines := soil reportedMatching: 'gave back'.
	self assert: lines size equals: 1.
	self assert: (lines first includesSubstring: 'SoilQueueTestUnprintableEntry that cannot be printed')
]

{ #category : #tests }
SoilQueueRetryTest >> testAnEntryThatIsGivenBackIsSaid [
	"an entry that keeps coming back after a wait would otherwise be seen only once it is
	parked, hours later. Each time it goes back is said, with how often in a row and how
	long it waits"

	| lines |
	self put: [ :target | SoilQueueTestContinuingEntry on: target steps: 3 ].
	self loseTheWorkerOn: self queue.

	lines := soil reportedMatching: 'gave back'.
	self assert: lines size equals: 1.
	self assert: (lines first includesSubstring: 'that lost its worker 1 time in a row, due again in').
	self assert: (lines first includesSubstring: 'SoilQueueTestContinuingEntry')
]

{ #category : #tests }
SoilQueueRetryTest >> testAWorkUnitThatRunsAgainAfterAConflictIsSaid [
	"what a work unit says about itself it says once for each attempt, and only the last one
	counted. The line in between tells them apart"

	| key queue lines |
	SoilQueueTestConflictingEntry conflictsToRaise: 1.
	key := self put: [ :target | SoilQueueTestConflictingEntry on: target ].
	queue := self queue.
	queue claim: key.
	queue work: key.

	lines := soil reportedMatching: 'concurrent change'.
	self assert: lines size equals: 1.
	self assert: (lines first includesSubstring: 'running it again (attempt 2 of 3)')
]

{ #category : #helpers }
SoilQueueRetryTest >> workspaceIn: aTransaction [
	"where the entries are: the workspace the description holds"

	^ (self descriptionIn: aTransaction) workspace
]
