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

My resumption semantics answer the one question an abort leaves open, and the queue
cannot answer it for me: *what holds afterwards*. An image can crash at any moment and
a rolling release interrupts work as a matter of routine, so every entry has to say
which of the three it is --

	#continuing    resume at the progress point; the progress has to be persisted
	#repeating     run again from the start; idempotence is a promise, not an assumption
	#compensating  clean up what the aborted attempt left behind, then start over

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
		'claimedAt',
		'resumption'
	],
	#category : #'Soil-Queue'
}

{ #category : #accessing }
SoilQueueEntry class >> resumption [
	"which of the three resumption semantics my instances follow -- see my class comment
	for why there is no default here"

	^ self subclassResponsibility
]

{ #category : #'instance creation' }
SoilQueueEntry class >> on: anObject [

	^ self new
		target: anObject;
		yourself
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

{ #category : #initialization }
SoilQueueEntry >> initialize [

	super initialize.
	state := #pending.
	resumption := self class resumption
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
