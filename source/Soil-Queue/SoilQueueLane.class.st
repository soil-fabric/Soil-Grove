"
The live half of a lane: what it decides about its entries.

A lane is a place the queue hands entries out from, with a limit for entries given back,
a backoff and a worker limit of its own -- how many of its workers may run at once.
Lanes share no places. Its stored half, SoilQueueLaneDescription, lies in the workspace
and says where its entries are; I say how they are tried again. The queue builds me from
both when it is created and again at every start, and after that nobody reads the
configuration for me: a changed setting holds from the next start on, the way it does
for a resident. Without a resident, they come from a description that is never stored,
handed to the queue where it is created. I have no setters: my description is the one
place the values are set and checked.

What I decide: whether an entry that was given back may come back once more, and how long
it waits before it does.

My values are only read once the queue runs, so asking me needs no lock. The one thing
of mine that changes, the key handed out last, is read and written under the queue's
mutex, where competing workers meet. I am never stored.
"
Class {
	#name : #SoilQueueLane,
	#superclass : #Object,
	#instVars : [
		'name',
		'orphanedRetryLimit',
		'backoffBase',
		'backoffCap',
		'workerLimit',
		'lastIssuedKey'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueLane class >> named: aSymbol configuredFrom: aDescription [

	^ self new
		setName: aSymbol;
		configureFrom: aDescription;
		yourself
]

{ #category : #retrying }
SoilQueueLane >> allowsOrphanedRetryOf: anEntry [
	"whether an entry that lost its worker may be given back once more. The limit reads
	like the restart limit of a resident: with a limit of two, an entry orphaned twice in a
	row comes back both times and the third orphaning is the one that parks it. Unlike a
	resident's restarts the count is of times in a row: a step of the entry that goes
	through in between ends the row"

	^ orphanedRetryLimit isNil or: [ anEntry orphanedRetries < orphanedRetryLimit ]
]

{ #category : #retrying }
SoilQueueLane >> backoffBase [

	^ backoffBase
]

{ #category : #retrying }
SoilQueueLane >> backoffCap [

	^ backoffCap
]

{ #category : #initialization }
SoilQueueLane >> configureFrom: aDescription [
	"take the values that hold for me off a description: what is set for me, else what is
	set for all lanes, else the defaults (#valueAt:forLane:). Called when the queue is
	created and at every start -- and only then"

	orphanedRetryLimit := aDescription valueAt: #orphanedRetryLimit forLane: name.
	backoffBase := aDescription valueAt: #backoffBase forLane: name.
	backoffCap := aDescription valueAt: #backoffCap forLane: name.
	workerLimit := aDescription valueAt: #workerLimit forLane: name
]

{ #category : #accessing }
SoilQueueLane >> lastIssuedKey [
	"the key handed out last, nil before the first. A grouped lane takes its groups in turn
	from behind this one, so that low group ids do not always win. Kept in memory only: after
	a start the turn begins at the front again, which costs nothing but one round"

	^ lastIssuedKey
]

{ #category : #accessing }
SoilQueueLane >> lastIssuedKey: anIndexKey [

	lastIssuedKey := anIndexKey
]

{ #category : #accessing }
SoilQueueLane >> name [

	^ name
]

{ #category : #retrying }
SoilQueueLane >> orphanedRetryLimit [

	^ orphanedRetryLimit
]

{ #category : #printing }
SoilQueueLane >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << name
]

{ #category : #retrying }
SoilQueueLane >> retryDelayAfter: anInteger [
	"the pause before retry number anInteger: the base, doubled for every failure before
	it, never longer than the cap"

	^ (backoffBase * (2 raisedTo: anInteger - 1)) min: backoffCap
]

{ #category : #initialization }
SoilQueueLane >> setName: aSymbol [

	name := aSymbol
]

{ #category : #accessing }
SoilQueueLane >> workerLimit [
	"how many of my workers may run at once: the places I have. Mine alone -- a lane full
	of due work cannot take the places another lane needs"

	^ workerLimit
]

