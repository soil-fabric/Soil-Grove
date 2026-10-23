"
Work that outlives the process which created it, handed out oldest-due first.

I am the live half, and I have to be: what I do is keep two workers off the same entry,
and that only works if every one of them talks to the same object. A database object
cannot be that -- two transactions materialize two of it, each with a mutex of its own
that excludes nobody. So the durable part is my description's and the coordinating part
is mine.

Being live as long as the database is open, carrying runtime state, and having a
persisted description is precisely what a resident is, so I am one. Nothing about that
forces a supervisor on anyone: created on my workspace (#onWorkspace:in:) and never
started, I still hand out entries, and without a supervisor there are no competing workers
for the mutex to arbitrate.

Mine is what competing workers meet at, and all of it lives in memory only: the mutex,
the set of keys that are out, the workers that are running, the wake time and my live
lanes. Keys, not entries -- an entry read in the transaction that selected it would
already be a snapshot of an older moment in the transaction that works on it. For the
same reason what I hand out is a key, and whoever takes it opens a transaction of its
own.

I hand out per lane. A lane is a place entries go out from with a retry budget and a
backoff of its own; its stored half lies in my workspace, its live half is a
SoilQueueLane I build at every start, and only then: a changed setting holds from the
next start on. Made by my description and not started yet -- loaded but switched off,
say -- I have no live lanes, and whoever asks for one hears that I am not started.
Without a resident, whoever creates me on a workspace gets the lanes built right there,
from a description that is never stored (#onWorkspace:configuredFrom:in:), and hands me
a changed one to change them (#configureFrom:in:).

Every lane has a worker limit, a count of places of its own; lanes share no places.
Before I start a worker for a lane there has to be a place free under its limit -- if
there is none, I start none and try again at the next wake.

Three roles, and the point of them is what each may not do. I hand out, and that is the
only place an entry is chosen. My process is the dispatcher: a step decides how many
workers there should be and when to wake next, and does no work itself. A QueueWorker
asks me, claims, works, gives back, and asks again. A stop reaches all of them through
me -- I stop handing out, and the workers run dry.

What happens to an entry is decided by the entry: what holds after a crash, what giving
up means for its target. How often it comes back and how soon is the lane's -- the limit
and the backoff.
"
Class {
	#name : #SoilQueue,
	#superclass : #SoilActiveResident,
	#instVars : [
		'mutex',
		'inFlight',
		'recovered',
		'workers',
		'clock',
		'wakeAt',
		'lanes'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueue class >> onWorkspace: aQueueWorkspace configuredFrom: aDescription in: aTransaction [
	"a queue without a resident: created on its workspace, its lanes built right here and
	configured from aDescription, which is never stored -- the values are set on it, as
	for a resident, and checked there. Whoever does this drives the queue itself, or
	starts it; a start keeps the lanes. Changed values come by configuring the queue
	again with a changed description (#configureFrom:in:)

	A supervisor of its own comes along, for the transactions the queue opens and the
	lines it emits. It supervises nothing: the queue is not registered anywhere"

	^ self new
		supervisor: aTransaction soil newResidentSupervisor;
		workspaceId: (aTransaction objectIdOf: aQueueWorkspace);
		configureFrom: aDescription in: aTransaction;
		yourself
]

{ #category : #'instance creation' }
SoilQueue class >> onWorkspace: aQueueWorkspace in: aTransaction [
	"the same with the defaults on every lane"

	^ self
		onWorkspace: aQueueWorkspace
		configuredFrom: SoilQueueDescription new
		in: aTransaction
]

{ #category : #accessing }
SoilQueue class >> soilTransientInstVars [
	"the inherited entries have to be repeated: a subclass declaration replaces its
	superclass's rather than adding to it, and a forgotten one would drag a process or a
	semaphore into a written graph"

	^ #( supervisor process workSignal runStrategy mutex inFlight recovered workers clock wakeAt lanes )
]

{ #category : #adding }
SoilQueue >> add: anEntry in: aTransaction [
	"put an entry in, in the caller's transaction. Not coordinated -- two writers do not
	get in each other's way here, because each entry gets a key of its own.

	An entry that says nothing about when it may run is ready now, by my clock: what sorts
	it is the time it was put in. One that sets a time keeps it.

	Into my first lane. Whoever has more than one says which, see #add:to:in:. The
	notification that wakes a worker is the caller's, after the commit: before it there is
	nothing to find."

	^ self
		add: anEntry
		to: (self workspaceIn: aTransaction) defaultLane name
		in: aTransaction
]

{ #category : #adding }
SoilQueue >> add: anEntry to: aLaneName in: aTransaction [
	"put an entry into the lane of that name, in the caller's transaction. A name that is
	no lane of mine is refused before anything is written: an entry under a prefix that
	no lane owns would be found by nobody, and by the next lane that is given the prefix.

	The one place an entry that says nothing about when it may run is made ready now, by
	my clock; my workspace refuses one.

	The answer is the key, in the form the index compares in."

	| workspace |
	workspace := self workspaceIn: aTransaction.
	anEntry readyAt ifNil: [ anEntry readyAt: self now ].
	^ workspace add: anEntry to: (workspace laneNamed: aLaneName)
]

{ #category : #lanes }
SoilQueue >> addLane: aSymbol format: aFormat [
	"a lane more, stored in my workspace under the next free marker. It takes entries at
	once, and I hand it out from when my lanes are built next, like any setting. With a
	resident that is my next start, which builds the lanes from my workspace and configures
	them from my description. Without one, my lanes are built where I am created on my
	workspace, and a start keeps them: the lane comes when my creator configures me again
	(#configureFrom:in:), or with a queue created anew there. So
	the place to add a lane is before a start -- a migration when the database opens, a
	registration before the queue runs.

	Nothing takes a lane out again: one that is not used any more costs its marker and a
	look at it in every step"

	self withTransactionDo: [ :txn |
		(self workspaceIn: txn) addLaneNamed: aSymbol format: aFormat.
		txn commit ]
]

{ #category : #working }
SoilQueue >> assignNextDueAt: aDateAndTime in: aTransaction [
	"the same for my first lane"

	^ self
		assignNextIn: self defaultLane
		dueAt: aDateAndTime
		in: aTransaction
]

{ #category : #working }
SoilQueue >> assignNextIn: aLane [
	"what a worker of aLane asks for, and the only way it gets an entry -- it never looks at
	the ordering itself.

	nil means 'nothing for you', and a worker that hears it ends. That is also how a stop
	arrives: the queue stops handing out, and the workers run dry by themselves. Nobody
	suspends a process from outside, because a process stopped inside a transaction leaves
	half-written state and held locks behind.

	A worker that hears nil ends, and whatever is due later is the dispatcher's again. The
	worker hands nothing on: its end is a signal (SoilQueueWorker>>#run), and the step that
	brings reads when the next entry falls due."

	^ self assignNextIn: aLane preferring: nil
]

{ #category : #working }
SoilQueue >> assignNextIn: aLane dueAt: aDateAndTime in: aTransaction [
	"the same with no key to carry on from"

	^ self
		assignNextIn: aLane
		dueAt: aDateAndTime
		preferring: nil
		in: aTransaction
]

{ #category : #working }
SoilQueue >> assignNextIn: aLane preferring: aKey [
	"what a worker of aLane asks for after it has worked on aKey, nil the first time. On a
	grouped lane that says which chain it is on, so that it can carry on with it -- see
	#assignNextIn:

	The read that selects is opened under the mutex, not before it. Soil fixes what a
	transaction sees when it opens, and a worker gives its entry back under the mutex after
	its commit: opened before, the read could be older than the last give-back, still hold
	an entry that is finished and gone, and find it no longer out -- it would be handed out
	again, the claim would fail, and two step errors would be counted for nothing.

	Opening a read reads the database version from Soil's control file: one small read,
	and at worst a wait behind a commit that is writing it. The scan that follows reads
	the index and the entries under the mutex anyway. What must not lie under it is a
	commit, and none does: the claim is a transaction of its own, outside. The mutex is
	reentrant, so the selection takes it again inside"

	self shouldStop ifTrue: [ ^ nil ].
	^ mutex critical: [
		self withTransactionDo: [ :txn |
			self assignNextIn: aLane dueAt: self now preferring: aKey in: txn ] ]
]

{ #category : #working }
SoilQueue >> assignNextIn: aLane dueAt: aDateAndTime preferring: aKey in: aTransaction [
	"hand out the next due entry of aLane that nobody else holds, remember that it is out,
	and answer its key -- or nil when nothing of aLane is due. On a lane ordered by due time
	that is the oldest due one; on a grouped lane the first of a group, preferring the group
	of aKey -- the entry the asking worker did last -- and otherwise taking the groups in
	turn from behind the one handed out last.

	Under the mutex, because this is where competing workers meet. What crosses the
	boundary is a key: the transaction this scanned in is not the one the work happens in.

	Nothing goes out for a lane I no longer hand out from: a start builds my lanes anew, and
	a worker of a lane from before it that is still running runs dry. The step its end
	brings starts workers on the new ones."

	^ mutex critical: [
		| workspace found |
		(lanes includes: aLane) ifFalse: [ ^ nil ].
		workspace := self workspaceIn: aTransaction.
		found := workspace
			nextDueAt: aDateAndTime
			in: (workspace laneNamed: aLane name)
			skipping: inFlight
			preferring: aKey
			after: aLane lastIssuedKey
			ifNone: [ nil ].
		found ifNotNil: [
			inFlight add: found.
			aLane lastIssuedKey: found ].
		found ]
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
	"the work unit of an entry failed at its work, and its transaction is gone. What is left
	to do is mine, in a transaction of my own: the entry gets to say so to its target
	(#giveUp:in:), and leaves the ordering -- which is all that done is.

	A failure at the work is a result. It is not tried again and not parked: a retry a far
	side would want is the entry's own business, a due time it sets itself, and a dead
	letter is kept for an entry that keeps coming back -- see #recover:.

	The error is kept for diagnosis. It is not counted as a step error: that count is what
	shows a crash loop, and a failure that was handled is none"

	lastStepError := anError.
	self withTransactionDo: [ :txn |
		| workspace entry |
		workspace := self workspaceIn: txn.
		entry := workspace entryAt: aKey.
		entry giveUp: anError in: txn.
		workspace removeKey: aKey.
		txn commit ]
]

{ #category : #working }
SoilQueue >> claim: aKey [
	"step 2 of a work unit: its own short transaction, committed before the work starts.
	Its only purpose is the crash case -- an entry found as claimed with no worker running
	was in the middle of something. It is not the mutual exclusion; under MVCC a claim
	written here is invisible to a transaction that is already open elsewhere."

	self withTransactionDo: [ :txn |
		((self workspaceIn: txn) entryAt: aKey) claimAt: self now.
		txn commit ]
]

{ #category : #accessing }
SoilQueue >> clock: aClock [
	"where I read the time from: anything that answers #now. Without one it is the wall
	clock. A test gives me one that stands still until it is moved, so that 'an hour later'
	is a statement rather than an hour"

	clock := aClock
]

{ #category : #configuring }
SoilQueue >> configureFrom: aDescription in: aTransaction [
	"build my lanes from the lanes stored in my workspace, each configured from
	aDescription -- what is set for it, else what is set for all lanes, else the defaults,
	its worker limit among them. With a resident this is called at every start, and only
	then: after that nobody reads the configuration for me. Without one, it is called where
	I am created on my workspace, and again by my creator with a changed description, as a
	start would.

	The lanes are built anew, and with them the turn of a grouped lane: it begins at the
	front again (#lastIssuedKey)"

	| workspace |
	workspace := self workspaceIn: aTransaction.
	lanes := workspace lanes collect: [ :each |
		SoilQueueLane named: each name configuredFrom: aDescription ]
]

{ #category : #working }
SoilQueue >> conflictLimit [
	"how often the same work unit is tried again after a write conflict before the conflict
	is treated as an error like any other. Small on purpose: a conflict that survives a few
	fresh reads is not a conflict any more, it is something that does not resolve, and
	trying for ever would hide it."

	^ 3
]

{ #category : #accessing }
SoilQueue >> defaultLane [
	"my first lane -- the only one until I have more"

	^ self liveLanes first
]

{ #category : #waking }
SoilQueue >> forgetWakeTime [
	"at the start of a step, which reads the ordering afresh. A wake time that has passed
	would otherwise stay behind if the step does not get to set a new one, and have the
	dispatcher step, and step again"

	wakeAt := nil
]

{ #category : #running }
SoilQueue >> freePlacesIn: aLane [
	"how many places of a lane are not taken, counted off the workers that are running --
	by name, so that a worker of a lane from before a start still counts"

	^ aLane workerLimit - (mutex critical: [
		workers count: [ :each | each lane name = aLane name ] ])
]

{ #category : #testing }
SoilQueue >> hasLiveLanes [
	"whether my lanes are built. A start builds them, and so does creating me on a
	workspace; a queue made by its description has none until it is started"

	^ lanes notEmpty
]

{ #category : #initialization }
SoilQueue >> initialize [

	super initialize.
	mutex := Mutex new.
	inFlight := Set new.
	workers := IdentitySet new.
	recovered := false.
	lanes := #(  )
]

{ #category : #testing }
SoilQueue >> isHolding: aKey [
	"whether an entry is out with someone right now. What tells an orphaned claim from a
	running one: an entry that says claimed and is not in here had its worker taken away"

	^ mutex critical: [ inFlight includes: aKey ]
]

{ #category : #accessing }
SoilQueue >> lane: aSymbol [
	"the live lane of that name, for a question about it"

	^ self liveLanes
		detect: [ :each | each name = aSymbol ]
		ifNone: [ self error: 'no live lane named ', aSymbol printString ]
]

{ #category : #accessing }
SoilQueue >> laneFor: aKey in: aQueueWorkspace [
	"the live lane an entry belongs to, found from its key"

	^ self lane: (aQueueWorkspace laneFor: aKey) name
]

{ #category : #accessing }
SoilQueue >> lanes [

	^ lanes
]

{ #category : #accessing }
SoilQueue >> liveLanes [
	"my lanes, for a question about one of them. Not started, I have none, and that is a
	different answer than a lane that is not there: the lane may well be in my workspace,
	waiting for the start that builds it"

	self hasLiveLanes ifFalse: [ ^ self error: 'the queue ' , self name printString , ' is not started' ].
	^ lanes
]

{ #category : #accessing }
SoilQueue >> name [
	"the same as my description's, one queue to a database. A constant, so that a process
	name or a status line needs no transaction -- sometimes while another one is already
	open"

	^ #queue
]

{ #category : #accessing }
SoilQueue >> nextDueTime [
	"when something of mine may run next, or nil when I hold nothing. For an embedder's
	external wakeup, and for its decision whether the database is quiet enough to close."

	^ self withTransactionDo: [ :txn |
		(self workspaceIn: txn) nextDueTimeAt: self now ]
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
	"read my configuration, then give the push at opening. A start is 'read the
	configuration, then run', for a restart as much as for the first one, so this is where
	my lanes are built from the workspace and the description.

	Work that was left lying around has to be found without anyone signalling for it: the
	signal that would have said so came before the restart and is gone with it. So every
	start raises the flag, whatever the workspace holds, and the first step does the rest:
	it gives back the claims the run before left, starts what is due and reads when the
	next entry will be. Asking the workspace first would not do -- it only knows about
	pending entries, and an orphaned claim alone would wait for the next signal.

	A queue created on its workspace without a resident has no description to read; its
	values came from the one it was created with, and they stay until its creator
	configures it again.

	Also asks again for claims that nobody holds. A restart does not make a new instance,
	so what was only asked once per instance would never be asked after the first start --
	and a worker that was taken away in the stop, or whose commit failed, leaves exactly
	such a claim behind."

	recovered := false.
	self descriptionId ifNotNil: [
		self configureFrom: (self descriptionIn: aTransaction) in: aTransaction ].
	self noteWork
]

{ #category : #recovery }
SoilQueue >> recover: aKey [
	"give one orphaned entry back, after it has said what holds now.

	The entry is asked first, every time and whatever comes after: its #resumeAfterAbortIn:
	runs before it is given back and before it is parked, in the same transaction, so that
	what the aborted attempt left behind is put right before another worker sees the entry
	-- and is not left lying under a dead letter either. What it does there is its own
	business, and there is no answer of mine to fall back on.

	Its own transaction, so that one entry whose answer throws does not keep the others
	from coming back. An entry that throws here stays claimed and is tried again at the
	next start, which is the right answer while the hook has no dead-lettering of its own.

	This is the one moment the queue learns that a worker went away, so it is where that is
	counted. An entry that has lost its worker as often in a row as its lane allows is not
	given back but parked: whatever took the worker with it would take the next one too.

	An entry that is given back waits first, by the curve of its lane: what took its worker
	away -- a commit that does not go through, a segment that is not
	there yet -- is often gone after a short while, and without the wait the budget would be
	used up in milliseconds. The key moves with the time, in the same commit."

	self withTransactionDo: [ :txn |
		| workspace entry lane |
		workspace := self workspaceIn: txn.
		entry := workspace entryAt: aKey.
		entry isClaimed ifFalse: [ ^ self ].
		entry resumeAfterAbortIn: txn.
		lane := self laneFor: aKey in: workspace.
		(lane allowsOrphanedRetryOf: entry)
			ifTrue: [
				entry noteOrphaned.
				entry releaseClaim.
				entry readyAt: self now + (lane retryDelayAfter: entry orphanedRetries).
				workspace moveKey: aKey for: entry ]
			ifFalse: [ workspace deadLetter: aKey ].
		txn commit ]
]

{ #category : #recovery }
SoilQueue >> recoverOrphanedClaims [
	"the push at opening: an entry that says claimed and that nobody is holding was in the
	middle of something when the image went away.

	Found over the entries and not over the index, because a claim does not change a key --
	the ordering cannot tell the two apart. What happens then is the entry's business and
	not mine: a continuing one keeps its progress, a repeating one starts over on its
	promise of idempotence, a compensating one is cleaned up first, and each says which in
	#resumeAfterAbortIn:. That is the whole reason the answer sits on the entry rather than
	in the queue.

	Once per start, not once per instance: #prepareIn: asks again, because a restart runs
	on the same instance. Within a start everything claimed after this is claimed by a
	worker of mine, and #isHolding: says so -- which is also why asking again at a start is
	safe: a worker of the run before that is still on its entry holds it.

	One orphan that cannot be given back does not keep the others waiting. It is reported
	like any failed step and stays claimed, and the next start tries it again."

	| orphans |
	recovered ifTrue: [ ^ self ].
	recovered := true.
	orphans := OrderedCollection new.
	self withTransactionDo: [ :txn |
		(self workspaceIn: txn) keysAndEntriesDo: [ :key :entry |
			(entry isClaimed and: [ (self isHolding: key) not ])
				ifTrue: [ orphans add: key ] ] ].
	orphans do: [ :each |
		[ self recover: each ]
			on: Error
			do: [ :anError | self handleStepError: anError ] ]
]

{ #category : #working }
SoilQueue >> release: aKey [
	"the entry is no longer out with anyone, whatever became of it"

	mutex critical: [ inFlight remove: aKey ifAbsent: [ nil ] ]
]

{ #category : #running }
SoilQueue >> runStep [
	"the dispatcher's step, and it does no work itself. One work unit here would block
	handing out, the wake time and the idle answer along with it, for as long as that unit
	takes.

	What it decides is how many workers there should be and when to be awake next, never
	who gets what -- that is the queue's own, under the mutex, because that is where
	competing workers meet. The wake time is set here and nowhere else."

	self forgetWakeTime.
	self recoverOrphanedClaims.
	self startWorkersForWhatIsDue
]

{ #category : #accessing }
SoilQueue >> runStrategyClass [

	^ SoilQueueRunStrategy
]

{ #category : #running }
SoilQueue >> startWorkerFor: aLane [
	"registered first, so that the place is taken from the moment the worker exists. If it
	cannot be started, it is taken out again: its #run, which does that when a worker ends,
	never began, and a place that nobody can give back would stay taken"

	| worker |
	worker := self workerFor: aLane.
	self workerStarting: worker.
	[ worker start ] ifCurtailed: [ self workerFinished: worker ]
]

{ #category : #running }
SoilQueue >> startWorkersForWhatIsDue [
	"as many workers as there is due work for, lane by lane, up to the places a lane has
	free, and nothing on stock -- and when the dispatcher has to be awake next. Both from one
	read of each lane, in one transaction for all of them, and this is the one place the
	wake time is set.

	The count leaves out the keys that are out, since a worker is on them already, and stops
	at the places free -- on a lane ordered by due time also at the first entry that is not
	due, so the read costs the same whether ten entries are waiting or ten thousand; a
	grouped lane looks at each group once. The number of waiting entries says nothing about
	how many workers are needed anyway -- it only says how long the working takes.

	Only a time still to come is a wake time, and a lane offers one only when its due work
	does not fill its free places. Due work is the workers' business: they are running for
	it, and a worker that ends signals, which brings the next step. So a lane full of due
	work does not hide the later time of another, and a lane with no place free is not read
	at all. The workers are started after the read, outside its transaction.

	The lanes and the keys that are out are taken before the transaction opens. Soil fixes
	what a transaction sees when it opens, and a lane is added to the workspace first and
	to my lanes second: taken in this order, every lane I read is one the transaction sees."

	| current held wanted time |
	self shouldStop ifTrue: [ ^ self ].
	current := lanes.
	held := mutex critical: [ inFlight copy ].
	wanted := OrderedCollection new.
	time := self withTransactionDo: [ :txn |
		| workspace now |
		workspace := self workspaceIn: txn.
		now := self now.
		current
			inject: nil
			into: [ :earliest :lane |
				| free |
				free := self freePlacesIn: lane.
				free > 0
					ifFalse: [ earliest ]
					ifTrue: [
						workspace
							dueAt: now
							in: (workspace laneNamed: lane name)
							skipping: held
							upTo: free
							do: [ :count :next |
								wanted add: lane -> count.
								(next isNil or: [ earliest notNil and: [ earliest <= next ] ])
									ifTrue: [ earliest ]
									ifFalse: [ next ] ] ] ] ].
	wakeAt := time.
	wanted do: [ :each | each value timesRepeat: [ self startWorkerFor: each key ] ]
]

{ #category : #working }
SoilQueue >> stepFailed: anError on: aKey [
	"an error got out of the step of the entry at aKey, and nobody booked it: the work unit
	did not fail at its work (that one is booked, see #book:for:), something around it did --
	the commit, a conflict that did not resolve, a record that could not be read, the
	bookkeeping itself. The entry still says claimed and
	no worker holds it any more, which is exactly what a lost worker leaves behind, so it goes
	back the same way: #recover: asks it what holds after the abort, counts it, waits, and
	parks it when the lane allows no more.

	Counted as a failed step first. If giving the entry back fails as well, that is counted
	too and the entry stays claimed: the next start finds it, see #recoverOrphanedClaims"

	self handleStepError: anError.
	[ self recover: aKey ]
		on: Error
		do: [ :anotherError | self handleStepError: anotherError ]
]

{ #category : #stopping }
SoilQueue >> terminateProcesses [
	"the hard way out, after the cooperative stop ran out of time. The workers go first:
	terminating the dispatcher leaves them running, and they are the ones holding entries"

	self workers do: [ :each | each terminate ].
	"nobody is left to take a place back. A worker that was terminated before its #run
	began never reaches the end of it, and would be counted for ever -- with a limit of one
	place that is no worker at all, and a queue that never says it is quiet"
	mutex critical: [ workers := IdentitySet new ].
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
	where no transaction is open. One writer, the dispatcher's own step, so no lock: a read
	from elsewhere sees the time a step set, or nil while a step is between forgetting the
	old one and setting the new one"

	^ wakeAt
]

{ #category : #working }
SoilQueue >> work: aKey [
	"step 3, with the one failure that is run again at once.

	A write conflict says that the worker was there and the work was fine and it simply did
	not happen: somebody else committed the same objects first. So the same work unit runs
	again at once -- no counter, no backoff, and above all no carrying on from the old
	snapshot. A fresh transaction is what makes the re-read happen, and it is the whole
	point of starting over rather than committing again.

	A work unit that fails at its work is booked afterwards, outside the loop: a conflict in
	the bookkeeping must not run the work again at once. It gets out of the step, and the
	entry goes back the way an orphan goes back."

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

{ #category : #running }
SoilQueue >> workerFinished: aWorker [
	"a worker ends by itself when nothing comes any more, which is also how a stop reaches
	it: the queue stops handing out and the workers run dry"

	mutex critical: [ workers remove: aWorker ifAbsent: [ nil ] ]
]

{ #category : #running }
SoilQueue >> workerFor: aLane [
	"a worker that takes its entries from aLane, not started yet"

	^ SoilQueueWorker on: self lane: aLane
]

{ #category : #accessing }
SoilQueue >> workers [
	"the workers that are running right now"

	^ mutex critical: [ workers asArray ]
]

{ #category : #running }
SoilQueue >> workerStarting: aWorker [
	"counted from the moment it exists, not from its first entry: the dispatcher asks how
	many are running before it decides to start another"

	mutex critical: [ workers add: aWorker ]
]

{ #category : #working }
SoilQueue >> workOnce: aKey [
	"one attempt at the work unit, and what follows from what it answers, in one commit.

	#more gives the claim back, and the entry stays in the ordering under the key its due
	time now asks for. Anything else is the end of the entry: it leaves the ordering, and
	nothing is written on it on the way out. A work unit that says 'again, but later' has moved its #readyAt,
	and the key is what sorts by it -- left where it was, the entry would be handed out
	again at once. The move goes with the result into the same commit, and it never reads
	the target: only the reference travels. An entry that did not move its due time keeps
	its key and is due again immediately.

	Two ways for the work unit to fail, told apart by the class of the error. One that is
	neither a SoilError nor a SoilSerializerError -- Soil's own two kinds, the serializer's
	lying below Soil's core -- is taken as a statement about the work: the whole
	transaction is discarded, and I answer the error, so that it is booked in a
	transaction of its own (#book:for:) -- the entry gives up. Soil's own are not -- a
	write conflict, a segment that is not there yet, a record Soil cannot read
	(SoilUnreadableRecord), a layout that cannot be migrated -- and they pass. #work: runs the
	unit again for a conflict; anything else gets out of the step, and the entry, still
	claimed, goes back the way an orphan goes back, after a wait, and is parked when its
	lane allows no more (#stepFailed:on:). Only the work unit is watched like this: an
	error from the bookkeeping around it or from the commit passes too, whatever its class.
	Otherwise I answer nil."

	self withTransactionDo: [ :txn |
		| workspace entry outcome |
		workspace := self workspaceIn: txn.
		entry := workspace entryAt: aKey.
		outcome := [ entry performIn: txn ]
			on: Error - SoilError - SoilSerializerError
			do: [ :anError | ^ anError ].
		outcome == #more
			ifTrue: [
				entry releaseClaim.
				workspace moveKey: aKey for: entry ]
			ifFalse: [ workspace removeKey: aKey ].
		txn commit ].
	^ nil
]
