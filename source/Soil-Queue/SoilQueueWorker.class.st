"
One worker on a lane of a queue: ask for an entry, claim it, do it, give it back, ask
again.

I do not scan. Which entry is mine is the queue's decision and nobody else's -- I would
otherwise have to know about the ordering, the section and what the others hold, and two
of us would take the same entry.

I have no stop protocol either, and that is deliberate. Stopping goes to the queue: it
stops handing out, and I end because nothing comes any more. A process suspended in the
middle of a transaction leaves half-written state and held locks behind, and the way to
never do that is to have no way to do it.

Nothing about me is written down. The state that has to survive a crash sits on the entry
-- it says claimed, and after a restart no worker holds it, which is exactly how an
orphaned claim is recognised. The other half of that is the queue's: the keys that are
out (#isHolding:), from the moment one is handed to me until I give it back, so it can
tell a claim with a worker from a claim without one.

A work unit that throws does not take me down. It is counted on the queue and I go on to
the next entry, because a transient failure must not cost a worker.
"
Class {
	#name : #SoilQueueWorker,
	#superclass : #Object,
	#instVars : [
		'queue',
		'lane',
		'process',
		'lastKey'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueWorker class >> on: aQueue [
	"a worker of the queue's first lane"

	^ self on: aQueue lane: aQueue defaultLane
]

{ #category : #'instance creation' }
SoilQueueWorker class >> on: aQueue lane: aLane [

	^ self new
		setQueue: aQueue lane: aLane;
		yourself
]

{ #category : #accessing }
SoilQueueWorker >> lane [
	"the lane I take entries from"

	^ lane
]

{ #category : #accessing }
SoilQueueWorker >> processName [

	^ 'soil queue worker ' , queue name , ' ' , lane name
]

{ #category : #running }
SoilQueueWorker >> run [
	"my whole life: entries until none comes any more. Ending is how a stop reaches me --
	the queue stops handing out and I run dry.

	Ending is also what I tell the queue, as work for its dispatcher. My place is free
	again, something may have come in while I was still counted -- an entry committed after
	my last empty look began, which the step in between found no place for -- and when the
	next entry falls due is the step's to read. I hand nothing on myself.

	Not while the queue is stopping: then I ended because it stopped handing out, there is
	no step to take, and a flag raised after the dispatcher has left would stay up -- the
	queue would never say it is quiet again until it is started anew"

	[ [ self runOnce notNil ] whileTrue ]
		ensure: [
			queue workerFinished: self.
			queue shouldStop ifFalse: [ queue noteWork ] ]
]

{ #category : #running }
SoilQueueWorker >> runOnce [
	"one entry, and answer its key -- nil when nothing came, which is what ends me.

	The release happens whatever happened, or an entry whose step failed would stay out of
	circulation. An error that gets out of the step -- the commit threw, a conflict did not
	resolve, the bookkeeping of a failed work unit threw -- is the queue's to deal with, and
	it does not cost me: a transient failure must not cost a worker. The queue counts it and
	gives the entry back, see SoilQueue>>#stepFailed:on:.

	The key I worked on last goes with the question for the next one: on a grouped lane
	that is how I carry on with my own chain."

	| key |
	key := queue assignNextIn: lane preferring: lastKey.
	key ifNil: [ ^ nil ].
	lastKey := key.
	[ [ queue claim: key.
	    queue work: key ]
		on: Error
		do: [ :anError | queue stepFailed: anError on: key ] ]
		ensure: [ queue release: key ].
	^ key
]

{ #category : #initialization }
SoilQueueWorker >> setQueue: aQueue lane: aLane [

	queue := aQueue.
	lane := aLane
]

{ #category : #running }
SoilQueueWorker >> start [

	process := [ self run ] forkNamed: self processName
]

{ #category : #stopping }
SoilQueueWorker >> terminate [
	"the hard way out, and only from the queue's own, after a cooperative stop ran out of
	time"

	process ifNotNil: [ :each | each terminate ]
]
