"
I am the wrapper that lies on a queue. Not the domain object itself: that keeps the
queue generic and keeps the domain object free of execution state.

What is generic is mine -- #state, #target, #claimedAt and the resumption semantics.
What the work *is* belongs to my subclasses, and that seam is deliberately narrow: a
queue must not know what the work does, what it costs, or which quota it counts
against.

I stay small on purpose, so that selection and diagnosis can read me without pulling
the target's object graph along. That only holds while the target is a cluster root of
its own: Object>>#soilClusterRootIn: is empty, so an ordinary reference materializes
the whole graph together with me.

I carry no field for my queue. Which queue I am on follows from the queue I lie in,
and a second source for the same fact is a duplicate that can disagree.

Two of my fields end up in my key rather than only on me. #eligibleAt is the sort
value, and it is a lower bound and not an appointment -- I am allowed to run from then
on, not scheduled for then, because a rate at the outlet can hold me back arbitrarily
long. #id is what makes the key unique, which the index needs: moving a key is refused
on an index with duplicate keys, and moving a key is what backoff does.

My resumption semantics answer the one question an abort leaves open, and the queue
cannot answer it for me: *what holds afterwards*. An image can crash at any moment and
a rolling release interrupts work as a matter of routine, so every entry has to say
which of the three it is --

	#continuing    resume at the progress point; the progress has to be persisted
	#repeating     run again from the start; idempotence is a promise, not an assumption
	#compensating  clean up what the aborted attempt left behind, then start over

Waiting is courtesy, not a guarantee. A maintenance run can let entries finish; a crash
cannot. Waiting lowers the number of repetitions -- the correctness is in the three
semantics above and nowhere else.

There is no default. Each of the three demands something different of the subclass,
and a default would hand out one of those demands silently. The compensating case is
the one that gets forgotten, and it produces most of the bugs.
"
Class {
	#name : #SoilQueueEntry,
	#superclass : #Object,
	#instVars : [
		'state',
		'target',
		'eligibleAt',
		'claimedAt',
		'resumption',
		'id',
		'progress'
	],
	#category : #'Soil-Queue'
}

{ #category : #accessing }
SoilQueueEntry class >> newId [
	"eight bytes that make my key unique among the entries that share my due time.

	Drawn at random rather than counted up. A counter would have to live somewhere that
	every enqueue writes to, and under MVCC a structure every writer touches is exactly
	where write conflicts come from -- the one thing the design goes out of its way to
	avoid. What it costs is order among entries of the very same millisecond, which the
	queue never promised: it hands out the oldest *due* entry, and due times are what it
	orders by."

	^ (UUID new asInteger \\ (256 raisedTo: 8)) asByteArrayOfSize: 8
]

{ #category : #'instance creation' }
SoilQueueEntry class >> on: anObject [

	^ self new
		target: anObject;
		yourself
]

{ #category : #accessing }
SoilQueueEntry class >> resumption [
	"which of the three resumption semantics my instances follow -- see my class comment
	for why there is no default here"

	^ self subclassResponsibility
]

{ #category : #accessing }
SoilQueueEntry >> claimAt: aDateAndTime [
	"step 2 of a worker's run: its own short transaction, committed before the work
	starts. Its only purpose is the crash case -- an entry found as #claimed with no
	worker running was in the middle of something. It is not mutual exclusion: under
	MVCC a claim written by one worker is invisible to another's already-open
	transaction, so exclusion is an in-memory mutex on the queue instead."

	self isPending ifFalse: [ ^ SoilQueueWrongEntryState signalFor: self expecting: #pending ].
	state := #claimed.
	claimedAt := aDateAndTime
]

{ #category : #accessing }
SoilQueueEntry >> claimedAt [
	"when the claim was taken, or nil while I am not claimed. What tells an orphaned
	claim from a running one, once the queue also knows which entries its workers hold"

	^ claimedAt
]

{ #category : #working }
SoilQueueEntry >> classifyError: anError [
	"translate an error out of my work unit into #retriable or #permanent. The queue calls
	overridden code and has to deal with whatever comes back without knowing what went
	wrong, which is why the translation is mine.

	The default is #permanent. The other way round, every new kind of work would silently
	get retries that nobody thought through. The case worth reading twice is a timeout: it
	does not mean nothing happened, because the call can have succeeded on the far side.
	Failures *before* the request went out -- connect refused, DNS, TLS -- are safe to
	repeat; failures after it are only safe when the far side is known to be idempotent."

	^ #permanent
]

{ #category : #working }
SoilQueueEntry >> compensateIn: aTransaction [
	"undo what an aborted attempt left behind, so a fresh attempt starts from a clean
	state. Only ever called for an entry whose resumption is #compensating. The other two
	have nothing to undo, which is why this is not an empty method they would inherit by
	accident"

	^ self subclassResponsibility
]

{ #category : #accessing }
SoilQueueEntry >> eligibleAt [
	"the time from which I may run. A lower bound, not an appointment: a rate at the outlet
	can hold me back arbitrarily long after it, and that is not a broken promise, because
	no promise about a point in time was made"

	^ eligibleAt
]

{ #category : #accessing }
SoilQueueEntry >> eligibleAt: aDateAndTime [
	"whoever changes this on an entry that already lies in a queue has to move its key with
	it, because the key is what sorts by this"

	eligibleAt := aDateAndTime
]

{ #category : #accessing }
SoilQueueEntry >> id [
	"eight bytes that tell me apart from the other entries that are due at the same time"

	^ id
]

{ #category : #initialization }
SoilQueueEntry >> initialize [

	super initialize.
	state := #pending.
	resumption := self class resumption.
	eligibleAt := DateAndTime now.
	id := self class newId
]

{ #category : #testing }
SoilQueueEntry >> isReadyToRunIn: aTransaction [
	"whether the queue can get to my work at all. Asked before the work unit runs, and the
	answer separates two things that look alike from outside: a wrapper that reads but
	points at nothing is infrastructure and there is no retrying it -- the answer is the
	dead letter. An error out of the work unit itself never comes through here; that one
	belongs to the work unit and its own classification.

	The default resolves the target, because that is the part that can be gone. Resolving
	has to be asked for: a proxy answers #isNil, #notNil and even #class without touching
	the store, so none of those would notice. A target that was never set is not the same
	as one that is gone, and it passes."

	^ [ target isSoilProxy ifTrue: [ target soilRealObject ].
	  true ]
		on: Error
		do: [ :anError | false ]
]

{ #category : #testing }
SoilQueueEntry >> isClaimed [

	^ state == #claimed
]

{ #category : #testing }
SoilQueueEntry >> isDeadLetter [

	^ state == #deadLetter
]

{ #category : #testing }
SoilQueueEntry >> isDone [

	^ state == #done
]

{ #category : #testing }
SoilQueueEntry >> isPending [

	^ state == #pending
]

{ #category : #accessing }
SoilQueueEntry >> markDeadLetter [
	"I could not be worked on at all -- my target is gone, my own materialization failed,
	something about me is broken. Dead lettering is reserved for that, and it parks me
	visibly instead of deleting me, because work that disappears without a trace is worse
	than work that sits there unfinished. Failing *at* the work is a different thing and
	ends in #markDone."

	state := #deadLetter.
	claimedAt := nil
]

{ #category : #accessing }
SoilQueueEntry >> markDone [
	"I am off the queue. Also the answer when the work unit failed for a reason of its
	own: a domain failure is a result, not a queue problem, and the target carries its own
	error state. Two places for the same fact would be one too many."

	self isClaimed ifFalse: [ ^ SoilQueueWrongEntryState signalFor: self expecting: #claimed ].
	state := #done.
	claimedAt := nil
]

{ #category : #working }
SoilQueueEntry >> performIn: aTransaction [
	"do one work unit in the transaction the queue opened, and answer what comes next:
	#more, #finished or #failed. No commit of my own -- the result, the index removal and
	any follow-up entry belong in the queue's single commit, so that the state where the
	work wants to go on and no entry is left cannot arise.

	Work and the question 'does it go on?' are one call rather than two because the answer
	is a property of the step that just ran. Keeping it between two calls would need a
	field that has no other reason to exist."

	^ self subclassResponsibility
]

{ #category : #printing }
SoilQueueEntry >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << state
]

{ #category : #accessing }
SoilQueueEntry >> progress [
	"where a resumable unit of work had got to, or nil when it never started.

	Only for entries that have no state machine of their own. A target that knows its own
	progress is the better place for it, and a second field beside it would be a duplicate
	that can disagree -- the wrapper then only says 'not finished', not where it stands."

	^ progress
]

{ #category : #accessing }
SoilQueueEntry >> progress: anObject [
	"set this *after* the effect it stands for, never before. A crash between the effect
	and the commit then costs a repetition; the other order loses the effect entirely, and
	the queue promises at least once rather than exactly once."

	progress := anObject
]

{ #category : #accessing }
SoilQueueEntry >> releaseClaim [
	"give me back to the queue after a claim turned out to be orphaned. What happens
	before this is what my resumption semantics say: a compensating entry is cleaned up
	first, a continuing one keeps its progress, a repeating one starts over as it is."

	self isClaimed ifFalse: [ ^ SoilQueueWrongEntryState signalFor: self expecting: #claimed ].
	state := #pending.
	claimedAt := nil
]

{ #category : #accessing }
SoilQueueEntry >> resumption [
	"#continuing, #repeating or #compensating. Kept as a field rather than asked of my
	class each time, so that cleaning up orphaned claims can read it off a materialized
	entry"

	^ resumption
]

{ #category : #accessing }
SoilQueueEntry >> state [
	"#pending, #claimed, #done or #deadLetter"

	^ state
]

{ #category : #accessing }
SoilQueueEntry >> target [
	"the domain object I stand for. A direct reference, not an object id: inside the model
	we navigate over objects, ids are for the outside boundary"

	^ target
]

{ #category : #accessing }
SoilQueueEntry >> target: anObject [

	target := anObject
]
