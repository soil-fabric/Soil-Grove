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
orphaned claim is recognised. What I carry is the other half of that: which entry is mine
*now*, so the queue can tell a claim with a worker from a claim without one.

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
		'currentKey'
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
SoilQueueWorker >> currentKey [
	"the entry I am on right now, or nil between two of them"

	^ currentKey
]

{ #category : #testing }
SoilQueueWorker >> isRunning [

	^ process notNil and: [ process isTerminated not ]
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
	the queue stops handing out and I run dry"

	[ [ self runOnce notNil ] whileTrue ]
		ensure: [ queue workerFinished: self ]
]

{ #category : #running }
SoilQueueWorker >> runOnce [
	"one entry, and answer its key -- nil when nothing came, which is what ends me.

	The release happens whatever happened, or a work unit that throws would take its entry
	out of circulation until the image restarts. A throwing work unit is counted on the
	queue and does not cost me: a transient failure must not cost a worker."

	| key |
	key := queue assignNextIn: lane.
	key ifNil: [ ^ nil ].
	currentKey := key.
	[ [ queue claim: key.
	    queue work: key ]
		on: Error
		do: [ :anError | queue handleStepError: anError ] ]
		ensure: [
			currentKey := nil.
			queue release: key ].
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
