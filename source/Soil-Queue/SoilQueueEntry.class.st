"
I am the wrapper that lies on a queue. Not the domain object itself: that keeps the
queue generic and keeps the domain object free of execution state.

What is generic is mine -- #target and #claimedAt. What the work *is* belongs to my
subclasses, and so does what holds after it was cut off. That seam is deliberately
narrow: a queue must not know what the work does, what it costs, or which quota it
counts against.

I stay small on purpose, so that selection and diagnosis can read me without pulling
the target's object graph along. That only holds while the target is a cluster root of
its own: Object>>#soilClusterRootIn: is empty, so an ordinary reference materializes
the whole graph together with me.

I carry no field for my queue. Which queue I am on follows from the queue I lie in,
and a second source for the same fact is a duplicate that can disagree.

For the same reason I have no field for my state. I am pending or claimed, and #claimedAt
says which: set from my claim until I am given back, nil before. Whether a worker still
has me is not mine to know but the live queue's (#isHolding:). Done and parked are not
states of mine but places. A finished entry has left the ordering and nothing refers to
it any more; a parked one lies in the dead letters, with the claim of the attempt it was
parked in. Saying so on me as well would be a second place for the same fact, and a
write of every finished entry for nothing.

On a lane ordered by due time two of my fields end up in my key rather than only on me.
#readyAt is the sort value, and it is a lower bound and not an appointment -- I am
allowed to run from then on, not scheduled for then, because the workers of my lane can
all be busy for arbitrarily long. #id is what makes the key unique, which the index needs:
moving a key is refused on an index with duplicate keys, and moving a key is what backoff
does there. A grouped lane keys me by my group instead and leaves #readyAt on me, so a
backoff holds up my group where I am (SoilQueueGroupedKeyFormat).

An abort leaves one question open, and the queue cannot answer it for me: *what holds
afterwards*. An image can crash at any moment and a rolling release interrupts work as a
matter of routine, so every subclass answers it, in #resumeAfterAbortIn:. The queue calls
it each time it gives me back or parks me after a loss -- a claim it finds at a start with
nobody holding it, or a step of mine that failed around my work unit -- and before either.
There are three answers, and a subclass gives one of them and says which --

	continuing    resume at the progress point; the progress has to be persisted, and
	              the hook has nothing to do
	repeating     run again from the start; idempotence is a promise, not an
	              assumption, and the hook has nothing to do
	compensating  clean up what the aborted attempt left behind, in the hook, then
	              start over

Where a continuing entry keeps its progress is its own business, not mine: a target with
a state machine of its own knows how far it got, and a field of the subclass does
otherwise -- a second one beside a target that knows would be a duplicate that can
disagree. Whichever it is, the progress is set *after* the effect it stands for, never
before. A crash between the effect and the commit then costs a repetition; the other
order loses the effect entirely, and the queue promises at least once rather than
exactly once.

I count how often I was given back: #orphanedRetries, once for each time I was found
claimed with no worker holding me -- my worker went away, a crash, a deploy, a rolling
release, or something around my work unit failed: a commit that did not go through, a
record that could not be read. It is not a count of attempts: a claim is taken for every
attempt, the first one included. A failure *at* my work is not counted at all. It is a
result: my target hears of it (#giveUp:in:), and I am done.

The count is of times in a row: a step of mine that goes through sets it back to nothing.
What it is read for -- the wait before the next try, and the limit of my lane -- is about
one step that keeps failing, not about how long I have been around. Counted over my whole
life, an entry that lives through many steps -- a flow instance -- would carry every
deploy it ever saw into the wait before its next step.

I say myself that a step went through (#noteStepDone); the queue cannot tell. #more is the
answer of a unit that only put itself off as well -- a throttle that asked to wait, a
switched-off target looked at again -- and setting the count back for one of those would
keep an entry whose step never goes through from ever reaching its limit.

Waiting is courtesy, not a guarantee. A maintenance run can let entries finish; a crash
cannot. Waiting lowers the number of repetitions -- the correctness is in the three
semantics above and nowhere else.

There is no default, and an empty method is one too: it would make every subclass that
never thought about it a repeating one, silently. Each of the three demands something
different of the subclass, and the compensating case is the one that gets forgotten and
produces most of the bugs. So the two answers that do nothing are written out all the
same, each with the sentence that says which of the two it is. A subclass that forgets
the hook would only find out at its first orphan; SoilQueueCleanCodeTest asks every
subclass that can work instead -- in an image that loads the tests of this package. A
project that loads only the queue does not get the question from here.
"
Class {
	#name : #SoilQueueEntry,
	#superclass : #Object,
	#instVars : [
		'target',
		'readyAt',
		'claimedAt',
		'id',
		'orphanedRetries'
	],
	#category : #'Soil-Queue'
}

{ #category : #accessing }
SoilQueueEntry class >> newId [
	"eight bytes that make my key unique where the rest of it is not: among the entries of my
	due time on a lane ordered by due time, among those of my group that drew my sequence
	number on a grouped lane.

	Drawn at random rather than counted up. A counter would have to live somewhere that
	every enqueue writes to, and under MVCC a structure every writer touches is exactly
	where write conflicts come from -- the one thing the design goes out of its way to
	avoid. What it costs on a lane ordered by due time is order among entries of the very
	same millisecond, which the queue never promised: it hands out the oldest *due* entry
	there, and due times are what it orders by."

	^ (UUID new asInteger \\ (256 raisedTo: 8)) asByteArrayOfSize: 8
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

	self isPending ifFalse: [ ^ SoilQueueWrongEntryState signalFor: self ].
	claimedAt := aDateAndTime
]

{ #category : #accessing }
SoilQueueEntry >> claimedAt [
	"when the claim was taken, or nil while I am not claimed -- the one field my state is
	read off (#state). What tells an orphaned claim from a running one, once the queue also
	knows which entries its workers hold.

	A parked entry keeps it: when its last attempt began is what a reader of the dead
	letters wants to know, and nobody hands out what lies there"

	^ claimedAt
]

{ #category : #accessing }
SoilQueueEntry >> readyAt [
	"the time from which I may run. A lower bound, not an appointment: busy workers can hold
	me back arbitrarily long after it, and that is not a broken promise, because no promise
	about a point in time was made.

	Nil until I am put into a queue unless my creator set one: the queue says 'now' then,
	because what counts is the time I was put in, not the time I was made"

	^ readyAt
]

{ #category : #accessing }
SoilQueueEntry >> readyAt: aDateAndTime [
	"whoever changes this on an entry that already lies in a queue has to have the workspace
	move its key (SoilQueueWorkspace>>#moveKey:for:): on a lane ordered by due time the key
	sorts by this, on a grouped lane it stays where it is. A work unit of mine may change it
	and answer #more: the queue then moves the key itself, in the same commit"

	readyAt := aDateAndTime
]

{ #category : #working }
SoilQueueEntry >> giveUp: anError in: aTransaction [
	"my work unit failed at its work, and that is my end: a failure at the work is a
	result, and it is not tried again. Called in the queue's bookkeeping transaction, after
	the one my work unit threw in is gone, and before I am taken out of the ordering in the
	same commit.

	The place for a subclass to put its target into its error state -- a flow instance
	that ends in error, say. What that means is the subclass's business; the queue only
	says when. Nothing by default"
]

{ #category : #accessing }
SoilQueueEntry >> groupId [
	"the group I belong to on a grouped lane, a non-negative integer: of one group, only one
	entry is out at a time, and they go out in the order they came in. Nil here -- an entry
	for a grouped lane answers it itself, off its target say. Read once, when I am put in;
	from then on my key holds the group (SoilQueueGroupedKeyFormat). On any other lane
	nobody asks"

	^ nil
]

{ #category : #accessing }
SoilQueueEntry >> id [
	"eight bytes that tell my key apart from another that is the same in everything else --
	see #newId"

	^ id
]

{ #category : #initialization }
SoilQueueEntry >> initialize [

	super initialize.
	id := self class newId.
	orphanedRetries := 0
]

{ #category : #testing }
SoilQueueEntry >> isClaimed [

	^ claimedAt notNil
]

{ #category : #testing }
SoilQueueEntry >> isPending [

	^ claimedAt isNil
]

{ #category : #accessing }
SoilQueueEntry >> noteOrphaned [
	"my worker went away while I was claimed, or my step failed around my work unit, and I
	am about to be given back. Counted here, at the one moment the queue learns of it, and
	not at the claim"

	orphanedRetries := orphanedRetries + 1
]

{ #category : #accessing }
SoilQueueEntry >> noteStepDone [
	"a step of mine went through. That ends a row: the count is of times in a row I was
	given back, so the next one waits from the start of the curve again, and my lane's
	limit starts over.

	Called from my #performIn:, so it is written with the step and goes with it when the
	commit does not go through. A unit that only put itself off does not call it. One that
	forgets to counts over its whole life -- it is parked sooner, never later"

	orphanedRetries := 0
]

{ #category : #accessing }
SoilQueueEntry >> orphanedRetries [
	"how often in a row I was found claimed with no worker holding me and was given back,
	since my last step that went through: the image went away, a deploy, a rolling release,
	a step that failed around my work unit rather than at it"

	^ orphanedRetries
]

{ #category : #working }
SoilQueueEntry >> performIn: aTransaction [
	"do one work unit in the transaction the queue opened, and answer what comes next:
	#more or #finished. A unit that has put a failure of its target on the target itself
	answers #finished too: that is my end, and the target carries the failure. One that
	throws fails at its work and is given up on (#giveUp:in:), or is given back when the
	error is Soil's (SoilQueue>>#workOnce:).
	No commit of my own -- the result, the index removal and any follow-up entry belong in
	the queue's single commit, so that the state where the work wants to go on and no entry
	is left cannot arise.

	Work and the question 'does it go on?' are one call rather than two because the answer
	is a property of the step that just ran. Keeping it between two calls would need a
	field that has no other reason to exist.

	A step that went through says so with #noteStepDone before it answers; a unit that only
	put itself off answers #more without it."

	^ self subclassResponsibility
]

{ #category : #printing }
SoilQueueEntry >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << self state
]

{ #category : #accessing }
SoilQueueEntry >> releaseClaim [
	"give me back to the queue: my work unit answered #more, or my claim turned out to be
	orphaned. Only in the second case is something cut off, and #resumeAfterAbortIn: comes
	first -- a compensating entry is cleaned up there, a continuing one keeps its progress,
	a repeating one starts over as it is."

	self isClaimed ifFalse: [ ^ SoilQueueWrongEntryState signalFor: self ].
	claimedAt := nil
]

{ #category : #working }
SoilQueueEntry >> resumeAfterAbortIn: aTransaction [
	"my worker went away while I was claimed, or something around my work unit failed, and
	I am about to be given back or parked: make true what has to hold for the next attempt.
	Called by the queue every time it finds me so, in the transaction that gives me back
	or parks me and before it does either, so what I write here is committed with that.

	Which of the three answers from my class comment a subclass gives is its own to say,
	and it says it here: a continuing or a repeating entry has nothing to do and says
	which of the two it is, a compensating one cleans up. An error here keeps me claimed
	until the next start of the queue.

	Asked of me and not of my class: what the queue holds may be a proxy that has not read
	me yet, and the class of a proxy is not mine"

	^ self subclassResponsibility
]

{ #category : #accessing }
SoilQueueEntry >> state [
	"#pending or #claimed, read off #claimedAt. In the dead letters it says nothing: being
	there is what says that I am parked"

	^ claimedAt
		ifNil: [ #pending ]
		ifNotNil: [ #claimed ]
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
