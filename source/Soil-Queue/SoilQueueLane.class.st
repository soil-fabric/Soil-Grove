"
The live half of a lane: how fast it runs, and what it decides about its entries.

A lane is a place the queue hands entries out from, with a pace of its own -- a rate, a
retry budget, a backoff -- and a worker pool it draws its workers from, which it may share
with other lanes. Its stored half, SoilQueueLaneDescription, lies in the workspace
and says where its entries are; I say how they go out. The queue builds me from both when
it is created and again at every start, and after that nobody reads the configuration
for me: a changed setting holds from the next start on, the way it does for a resident.
Without a resident, whoever creates the queue sets my values in code.

What I decide: whether an entry may be tried once more after a failure or after losing
its worker, how long it waits before the next try, and whether the rate lets one more
go out now. What went out lately I count myself, one counter per lane -- two lanes with
two rates must not share a count.

I am asked under the queue's mutex, like everything competing workers meet at, and I am
never stored.
"
Class {
	#name : #SoilQueueLane,
	#superclass : #Object,
	#instVars : [
		'name',
		'rateLimit',
		'ratePeriod',
		'failureRetryLimit',
		'orphanedRetryLimit',
		'backoffBase',
		'backoffCap',
		'rateCounter',
		'pool'
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
SoilQueueLane >> allowsFailureRetryOf: anEntry [
	"whether an entry whose work unit failed retriably may be tried once more. With a limit
	of three, three retries happen and the fourth failure is the one that gives up"

	^ anEntry failureRetries < failureRetryLimit
]

{ #category : #retrying }
SoilQueueLane >> allowsOrphanedRetryOf: anEntry [
	"whether an entry that lost its worker may be given back once more. Counted like the
	restarts of a resident: with a limit of two, two orphaned entries come back and the
	third orphaning is the one that parks it"

	^ orphanedRetryLimit isNil or: [ anEntry orphanedRetries < orphanedRetryLimit ]
]

{ #category : #retrying }
SoilQueueLane >> backoffBase: aDuration [

	backoffBase := aDuration
]

{ #category : #retrying }
SoilQueueLane >> backoffCap: aDuration [

	backoffCap := aDuration
]

{ #category : #initialization }
SoilQueueLane >> configureFrom: aDescription [
	"take my values off a description, defaults included. Called when the queue is created
	and at every start -- and only then"

	rateLimit := aDescription rateLimit.
	ratePeriod := aDescription ratePeriod.
	failureRetryLimit := aDescription failureRetryLimit.
	orphanedRetryLimit := aDescription orphanedRetryLimit.
	backoffBase := aDescription backoffBase.
	backoffCap := aDescription backoffCap
]

{ #category : #retrying }
SoilQueueLane >> failureRetryLimit: anInteger [

	anInteger < 0 ifTrue: [
		^ self error: 'a negative number of retries cannot be used up' ].
	failureRetryLimit := anInteger
]

{ #category : #initialization }
SoilQueueLane >> initialize [

	super initialize.
	rateCounter := SoilQueueRateCounter new
]

{ #category : #accessing }
SoilQueueLane >> name [

	^ name
]

{ #category : #rate }
SoilQueueLane >> noteIssueAt: aDateAndTime [
	"an entry went out, and counts against my rate for its period. Nothing to count without
	a rate"

	rateLimit ifNil: [ ^ self ].
	rateCounter noteIssueAt: aDateAndTime
]

{ #category : #retrying }
SoilQueueLane >> orphanedRetryLimit: anInteger [

	(anInteger notNil and: [ anInteger < 0 ]) ifTrue: [
		^ self error: 'a negative number of retries cannot be used up' ].
	orphanedRetryLimit := anInteger
]

{ #category : #accessing }
SoilQueueLane >> pool [
	"the worker pool my workers take their places in"

	^ pool
]

{ #category : #accessing }
SoilQueueLane >> pool: aWorkerPool [

	pool := aWorkerPool
]

{ #category : #printing }
SoilQueueLane >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << name
]

{ #category : #rate }
SoilQueueLane >> rateAllowanceAt: aDateAndTime ifNone: aBlock [
	"how many entries my rate lets out at aDateAndTime -- or what aBlock answers when I have
	no rate, since then the bound is somebody else's"

	^ rateLimit
		ifNil: [ aBlock value ]
		ifNotNil: [ :limit |
			rateCounter allowanceAt: aDateAndTime limit: limit period: ratePeriod ]
]

{ #category : #rate }
SoilQueueLane >> rateFreeAt: aDateAndTime [
	"from when my rate lets the next entry out: aDateAndTime itself when it has room, and
	always without a rate"

	^ rateLimit
		ifNil: [ aDateAndTime ]
		ifNotNil: [ :limit |
			rateCounter freeAt: aDateAndTime limit: limit period: ratePeriod ]
]

{ #category : #rate }
SoilQueueLane >> rateLimit: anInteger per: aDuration [
	"no more than anInteger entries handed out in any period of aDuration"

	anInteger < 1 ifTrue: [ ^ self error: 'a rate that lets nothing out would stop the lane' ].
	rateLimit := anInteger.
	ratePeriod := aDuration
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
