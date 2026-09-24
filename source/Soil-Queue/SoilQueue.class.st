"
Work that outlives the process which created it, handed out oldest-due first.

I am the live half, and I have to be: what I do is keep two workers off the same entry,
and that only works if every one of them talks to the same object. A database object
cannot be that -- two transactions materialize two of it, each with a mutex of its own
that excludes nobody. So the durable part is my description's and the coordinating part
is mine.

Being live as long as the database is open, carrying runtime state, and having a
persisted description is precisely what a resident is, so I am one. Nothing about that
forces a supervisor on anyone: created and not started, I still hand out entries, and
without a supervisor there are no competing workers for the mutex to arbitrate.

Mine are the mutex and the set of keys that are out. Keys, not entries -- an entry read
in the transaction that selected it would already be a snapshot of an older moment in
the transaction that works on it. For the same reason what I hand out is a key, and
whoever takes it opens a transaction of its own.

One work unit at a time for now. How many run at once is the dispatcher's question and
comes with the QueueWorker; the transaction boundaries below are already the ones that
several of them will keep.
"
Class {
	#name : #SoilQueue,
	#superclass : #SoilActiveResident,
	#instVars : [
		'name',
		'mutex',
		'inFlight',
		'recovered',
		'workers',
		'clock',
		'wakeAt'
	],
	#category : #'Soil-Queue'
}

{ #category : #accessing }
SoilQueue class >> soilTransientInstVars [
	"the inherited entries have to be repeated: a subclass declaration replaces its
	superclass's rather than adding to it, and a forgotten one would drag a process or a
	semaphore into a written graph"

	^ #( supervisor process workSignal runStrategy mutex inFlight recovered workers clock wakeAt )
]

{ #category : #adding }
SoilQueue >> add: anEntry in: aTransaction [
	"put an entry in, in the caller's transaction. Not coordinated -- two writers do not
	get in each other's way here, because each entry gets a key of its own"

	^ (self descriptionIn: aTransaction) add: anEntry
]

{ #category : #working }
SoilQueue >> assignNext [
	"what a worker asks for, and the only way it gets an entry -- it never looks at the
	ordering itself.

	nil means 'nothing for you', and a worker that hears it ends. That is also how a stop
	arrives: the queue stops handing out, and the workers run dry by themselves. Nobody
	suspends a process from outside, because a process stopped inside a transaction leaves
	half-written state and held locks behind.

	A worker that hears nil ends, and whatever is due later is the dispatcher's again. The
	scan that found nothing due found the next due time on its way, so that is handed to the
	dispatcher here -- otherwise an entry pushed out to later by the work unit that just
	ran would wake nobody."

	self shouldStop ifTrue: [ ^ nil ].
	^ self withTransactionDo: [ :txn |
		self assignNextDueAt: self now in: txn ifNone: [ :time |
			time ifNotNil: [ self noteNextDueAt: time ].
			nil ] ]
]

{ #category : #working }
SoilQueue >> assignNextDueAt: aDateAndTime in: aTransaction ifNone: aBlock [
	"hand out the oldest due entry that nobody else holds, and remember that it is out.

	Under the mutex, because this is where competing workers meet. What crosses the
	boundary is a key: the transaction this scanned in is not the one the work happens in."

	| key nextTime |
	key := mutex critical: [
		| found |
		found := (self descriptionIn: aTransaction)
			nextDueAt: aDateAndTime
			skipping: inFlight
			ifNone: [ :time | nextTime := time. nil ].
		found ifNotNil: [ inFlight add: found ].
		found ].
	^ key ifNil: [ aBlock cull: nextTime ]
]

{ #category : #testing }
SoilQueue >> basicIsIdle [
	"not idle while a worker is on something. The embedder reads this to decide whether the
	database is quiet enough to close, and a worker in the middle of a transaction is the
	case that decision is about"

	^ super basicIsIdle and: [ mutex critical: [ workers isEmpty ] ]
]

{ #category : #working }
SoilQueue >> book: anError for: aKey [
	"the work unit of an entry threw, and its transaction is gone. What is left to do is
	mine, in a transaction of my own: ask the entry what the error means, and then either
	put it off and count it, or give up on it.

	Put off: #failureRetries goes up, the due time moves out by the delay the entry asks
	for, and the key moves with it -- the dispatcher reads the next wake time off the
	ordering, and the worker that runs dry hands it on. Given up: the entry gets to say so
	to its target (#giveUp:in:), and is done. A failure the entry cannot get past is a
	result, not a dead letter; that one is kept for entries nobody could get to at all.

	The error is kept for diagnosis. It is not counted as a step error: that count is what
	shows a crash loop, and a failure that was handled is none"

	lastStepError := anError.
	self withTransactionDo: [ :txn |
		| description entry |
		description := self descriptionIn: txn.
		entry := description entryAt: aKey.
		((entry classifyError: anError) == #retriable
			and: [ description allowsFailureRetryOf: entry ])
			ifTrue: [
				entry noteFailure.
				entry eligibleAt: self now
					+ (entry retryDelayAfter: entry failureRetries under: description).
				entry releaseClaim.
				description moveKey: aKey for: entry ]
			ifFalse: [
				entry giveUp: anError in: txn.
				description removeKey: aKey.
				entry markDone ].
		txn commit ]
]

{ #category : #working }
SoilQueue >> claim: aKey [
	"step 2 of a work unit: its own short transaction, committed before the work starts.
	Its only purpose is the crash case -- an entry found as claimed with no worker running
	was in the middle of something. It is not the mutual exclusion; under MVCC a claim
	written here is invisible to a transaction that is already open elsewhere."

	self withTransactionDo: [ :txn |
		((self descriptionIn: txn) entryAt: aKey) claimAt: self now.
		txn commit ]
]

{ #category : #accessing }
SoilQueue >> clock: aClock [
	"where I read the time from: anything that answers #now. Without one it is the wall
	clock. A test gives me one that stands still until it is moved, so that 'an hour later'
	is a statement rather than an hour"

	clock := aClock
]

{ #category : #working }
SoilQueue >> conflictLimit [
	"how often the same work unit is tried again after a write conflict before the conflict
	is treated as an error like any other. Small on purpose: a conflict that survives a few
	fresh reads is not a conflict any more, it is something that does not resolve, and
	trying for ever would hide it."

	^ 3
]

{ #category : #waking }
SoilQueue >> forgetWakeTime [
	"at the start of a step, which reads the ordering afresh. A wake time that has passed
	would otherwise stay behind and have the dispatcher step, and step again"

	mutex critical: [ wakeAt := nil ]
]

{ #category : #initialization }
SoilQueue >> initialize [

	super initialize.
	mutex := Mutex new.
	inFlight := Set new.
	workers := IdentitySet new.
	recovered := false
]

{ #category : #testing }
SoilQueue >> isHolding: aKey [
	"whether an entry is out with someone right now. What tells an orphaned claim from a
	running one: an entry that says claimed and is not in here had its worker taken away"

	^ mutex critical: [ inFlight includes: aKey ]
]

{ #category : #accessing }
SoilQueue >> name [
	"carried rather than looked up: my name ends up in a process name and in status lines,
	and a transaction for a label would be one too many -- sometimes while another one is
	already open"

	^ name
]

{ #category : #accessing }
SoilQueue >> name: aSymbol [

	name := aSymbol
]

{ #category : #accessing }
SoilQueue >> nextDueTime [
	"when something of mine may run next, or nil when I hold nothing. For an embedder's
	external wakeup, and for its decision whether the database is quiet enough to close."

	^ self withTransactionDo: [ :txn |
		(self descriptionIn: txn) nextDueTimeAt: self now ]
]

{ #category : #waking }
SoilQueue >> noteNextDueAt: aDateAndTime [
	"something falls due at aDateAndTime, and the dispatcher has to be awake by then. The
	earlier of two times wins: a later one does not make an earlier entry any less due.
	The dispatcher is signalled but not handed a flag, because nothing is due yet -- it
	only has to measure its sleep again"

	mutex critical: [
		wakeAt := wakeAt
			ifNil: [ aDateAndTime ]
			ifNotNil: [ :current | current min: aDateAndTime ] ].
	self wakeUp
]

{ #category : #accessing }
SoilQueue >> now [
	"the one place I ask for the time. Due times are compared against it, a claim is
	stamped with it, and the wake time is measured from it -- one source, so that they
	cannot disagree"

	^ clock
		ifNil: [ DateAndTime now ]
		ifNotNil: [ :aClock | aClock now ]
]

{ #category : #running }
SoilQueue >> prepareIn: aTransaction [
	"the push at opening. Work that was left lying around has to be found without anyone
	signalling for it: the signal that would have said so came before the restart and is
	gone with it.

	This only raises the flag; the first work unit does the rest. An entry that is not due
	yet raises it too: the step that finds nothing due is the one that reads when it will
	be, and the dispatcher sleeps until then."

	((self descriptionIn: aTransaction) nextDueTimeAt: self now)
		ifNotNil: [ self noteWork ]
]

{ #category : #recovery }
SoilQueue >> recover: aKey [
	"give one orphaned entry back, the way its own semantics say.

	Its own transaction, so that one entry whose compensation throws does not keep the
	others from coming back. A compensating entry that throws here stays claimed and is
	tried again at the next pass, which is the right answer while the cleanup step has no
	dead-lettering of its own.

	This is the one moment the queue learns that a worker went away, so it is where that is
	counted. An entry that has lost its worker as often as the description allows is not
	given back but parked: whatever took the worker with it would take the next one too.
	Compensated first all the same, so that what it left behind is not left lying under a
	dead letter."

	self withTransactionDo: [ :txn |
		| description entry |
		description := self descriptionIn: txn.
		entry := description entryAt: aKey.
		entry isClaimed ifFalse: [ ^ self ].
		entry resumption == #compensating ifTrue: [ entry compensateIn: txn ].
		(description allowsOrphanedRetryOf: entry)
			ifTrue: [
				entry noteOrphaned.
				entry releaseClaim ]
			ifFalse: [ description deadLetter: aKey ].
		txn commit ]
]

{ #category : #recovery }
SoilQueue >> recoverOrphanedClaims [
	"the push at opening: an entry that says claimed and that nobody is holding was in the
	middle of something when the image went away.

	Found over the entries and not over the index, because a claim does not change a key --
	the ordering cannot tell the two apart. What happens then is the entry's business and
	not mine: a continuing one keeps its progress, a repeating one starts over on its
	promise of idempotence, a compensating one is cleaned up first. That is the whole
	reason the semantics sit on the entry rather than in the queue.

	Once per lifetime. Everything claimed after this is claimed by a worker of mine, and
	#isHolding: says so."

	| orphans |
	recovered ifTrue: [ ^ self ].
	recovered := true.
	orphans := OrderedCollection new.
	self withTransactionDo: [ :txn |
		(self descriptionIn: txn) keysAndEntriesDo: [ :key :entry |
			(entry isClaimed and: [ (self isHolding: key) not ])
				ifTrue: [ orphans add: key ] ] ].
	orphans do: [ :each | self recover: each ]
]

{ #category : #working }
SoilQueue >> release: aKey [
	"the entry is no longer out with anyone, whatever became of it"

	mutex critical: [ inFlight remove: aKey ifAbsent: [ nil ] ]
]

{ #category : #waking }
SoilQueue >> rememberNextDueTime [
	"the last thing a step does: read when the first entry of the ordering falls due. Only
	a time still to come is a wake time. One that has come is the workers' business -- they
	are running for it, and the last of them to run dry hands on what it found"

	| time |
	time := self nextDueTime.
	(time notNil and: [ time > self now ]) ifFalse: [ ^ self ].
	mutex critical: [
		wakeAt := wakeAt
			ifNil: [ time ]
			ifNotNil: [ :current | current min: time ] ]
]

{ #category : #running }
SoilQueue >> runStep [
	"the dispatcher's step, and it does no work itself. One work unit here would block
	handing out, the wake time and the idle answer along with it, for as long as that unit
	takes.

	What it decides is how many workers there should be, never who gets what -- that is
	the queue's own, under the mutex, because that is where competing workers meet."

	self forgetWakeTime.
	self recoverOrphanedClaims.
	self startWorkersForWhatIsDue.
	self rememberNextDueTime
]

{ #category : #accessing }
SoilQueue >> runStrategyClass [

	^ SoilQueueRunStrategy
]

{ #category : #running }
SoilQueue >> startWorker [

	| worker |
	worker := SoilQueueWorker on: self.
	self workerStarting: worker.
	worker start
]

{ #category : #running }
SoilQueue >> startWorkersForWhatIsDue [
	"as many workers as there is due work for, up to the limit, and nothing on stock.

	The count stops at the limit and at the first entry that is not due, so the scan costs
	the same whether ten entries are waiting or ten thousand. The number of waiting entries
	says nothing about how many workers are needed anyway -- it only says how long the
	working takes."

	| wanted running |
	self shouldStop ifTrue: [ ^ self ].
	wanted := self withTransactionDo: [ :txn |
		| description |
		description := self descriptionIn: txn.
		(description dueCountAt: self now upTo: description workerLimit)
			min: description workerLimit ].
	running := mutex critical: [ workers size ].
	(wanted - running) timesRepeat: [ self startWorker ]
]

{ #category : #stopping }
SoilQueue >> terminateProcesses [
	"the hard way out, after the cooperative stop ran out of time. The workers go first:
	terminating the dispatcher leaves them running, and they are the ones holding entries"

	self workers do: [ :each | each terminate ].
	super terminateProcesses
]

{ #category : #running }
SoilQueue >> tick [
	"the dispatcher's sleep is measured in the time that was left when it began. A wall
	clock set forward in the meantime would let it oversleep, so every tick has it look at
	the time again. That costs a comparison, not a step: a wake-up with nothing due puts it
	straight back to sleep"

	super tick.
	self wakeUp
]

{ #category : #waking }
SoilQueue >> timeUntilWake [
	"how long the dispatcher may sleep before the next entry falls due, never less than
	nothing. nil when there is no wake time: then it sleeps until somebody signals"

	^ self wakeAt ifNotNil: [ :time | (time - self now) max: 0 seconds ]
]

{ #category : #waking }
SoilQueue >> wakeAt [
	"when the dispatcher has to be awake because an entry falls due, or nil when nothing
	is known to fall due. Kept in memory and nowhere else: it is read between two steps,
	where no transaction is open"

	^ mutex critical: [ wakeAt ]
]

{ #category : #working }
SoilQueue >> work: aKey [
	"step 3, with the one failure that is neither of the two the entry knows about.

	A write conflict says that the worker was there and the work was fine and it simply did
	not happen: somebody else committed the same objects first. So the same work unit runs
	again at once -- no counter, no backoff, and above all no carrying on from the old
	snapshot. A fresh transaction is what makes the re-read happen, and it is the whole
	point of starting over rather than committing again.

	A work unit that throws is booked afterwards, outside the loop: a conflict in the
	bookkeeping must not run the work again."

	| attempts failure |
	attempts := 0.
	[ attempts := attempts + 1.
	  [ failure := self workOnce: aKey.
	    true ]
		on: SoilObjectHasConcurrentChange
		do: [ :aConflict |
			attempts >= self conflictLimit ifTrue: [ aConflict pass ].
			false ] ]
		whileFalse.
	failure ifNotNil: [ self book: failure for: aKey ]
]

{ #category : #working }
SoilQueue >> workOnce: aKey [
	"one attempt at the work unit, and what follows from what it answers, in one commit.

	#more gives the claim back, and the entry stays in the ordering under the key its due
	time now asks for. A work unit that says 'again, but later' has moved its #eligibleAt,
	and the key is what sorts by it -- left where it was, the entry would be handed out
	again at once. The move goes with the result into the same commit, and it never reads
	the target: only the reference travels. An entry that did not move its due time keeps
	its key and is due again immediately.

	An entry that is not ready to run never gets as far as its work unit: something it
	needs is gone, no repetition will bring it back, and it is parked as a dead letter
	instead. That is infrastructure and is kept apart from failing *at* the work, which is
	a result and ends in #markDone.

	A work unit that throws discards the whole transaction, and I answer the error, so that
	it is booked in a transaction of its own (#book:for:). Only an error out of the work
	unit is answered. One from anywhere else -- the commit, the store -- is no statement
	about the work, and classifying it would let the entry's #permanent throw away work
	that never got to run; it passes, and the entry stays claimed for the recovery pass.
	A write conflict passes too, wherever it comes from: it is neither of the two failures
	an entry knows about, and #work: runs the unit again for it. Otherwise I answer nil."

	self withTransactionDo: [ :txn |
		| description entry outcome |
		description := self descriptionIn: txn.
		entry := description entryAt: aKey.
		(entry isReadyToRunIn: txn)
			ifFalse: [
				description deadLetter: aKey.
				txn commit.
				^ self ].
		outcome := [ entry performIn: txn ]
			on: Error
			do: [ :anError |
				(anError isKindOf: SoilObjectHasConcurrentChange) ifTrue: [ anError pass ].
				^ anError ].
		outcome == #more
			ifTrue: [
				entry releaseClaim.
				description moveKey: aKey for: entry ]
			ifFalse: [
				description removeKey: aKey.
				entry markDone ].
		txn commit ].
	^ nil
]

{ #category : #running }
SoilQueue >> workerFinished: aWorker [
	"a worker ends by itself when nothing comes any more, which is also how a stop reaches
	it: the queue stops handing out and the workers run dry"

	mutex critical: [ workers remove: aWorker ifAbsent: [ nil ] ]
]

{ #category : #running }
SoilQueue >> workerStarting: aWorker [
	"counted from the moment it exists, not from its first entry: the dispatcher asks how
	many are running before it decides to start another"

	mutex critical: [ workers add: aWorker ]
]

{ #category : #accessing }
SoilQueue >> workers [
	"the workers that are running right now"

	^ mutex critical: [ workers asArray ]
]
