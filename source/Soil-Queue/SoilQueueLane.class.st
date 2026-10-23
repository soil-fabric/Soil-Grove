"
The live half of a lane: what it decides about its entries.

A lane is a place the queue hands entries out from, with a limit for entries given back,
a backoff and a worker limit of its own -- how many of its workers may run at once.
Lanes share no places. Its stored half, SoilQueueLaneDescription, lies in the workspace
and says where its entries are; I say how they are tried again. The queue builds me from
both when it is created and again at every start, and after that nobody reads the
configuration for me: a changed setting holds from the next start on, the way it does
for a resident. Without a resident, whoever creates the queue sets my values in code.

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
SoilQueueLane class >> named: aSymbol [
	"a lane with the default configuration -- the one a description answers when nothing is
	set on it, so that the defaults are written down in one place"

	^ self named: aSymbol configuredFrom: SoilQueueDescription new
]

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
SoilQueueLane >> backoffBase: aDuration [

	backoffBase := aDuration
]

{ #category : #retrying }
SoilQueueLane >> backoffCap [

	^ backoffCap
]

{ #category : #retrying }
SoilQueueLane >> backoffCap: aDuration [

	backoffCap := aDuration
]

{ #category : #initialization }
SoilQueueLane >> configureFrom: aDescription [
	"take my values off a description, defaults included. Called when the queue is created
	and at every start -- and only then"

	orphanedRetryLimit := aDescription orphanedRetryLimit.
	backoffBase := aDescription backoffBase.
	backoffCap := aDescription backoffCap.
	workerLimit := aDescription workerLimit
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

{ #category : #retrying }
SoilQueueLane >> orphanedRetryLimit: anInteger [

	(anInteger notNil and: [ anInteger < 0 ]) ifTrue: [
		^ self error: 'a negative number of retries cannot be used up' ].
	orphanedRetryLimit := anInteger
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

{ #category : #accessing }
SoilQueueLane >> workerLimit: anInteger [

	anInteger < 1 ifTrue: [ ^ self error: 'a lane with no place would never let a worker run' ].
	workerLimit := anInteger
]
