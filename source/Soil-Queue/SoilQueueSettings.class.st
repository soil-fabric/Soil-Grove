"
How often and how fast a queue runs, as it stood when the queue started: the worker
limit, the rate, the two retry budgets and the backoff curve.

My description is where these are kept and changed; I am what the queue reads while it
runs. The queue takes me when it is created and again at every start, so a changed
setting holds from the next start on -- a restart of the resident, which reads its
configuration and then runs. Nobody watches the description for changes, and nothing
here makes a setting change in the middle of a run behind anybody's back.

I am never stored. The queue that holds me is not stored either.
"
Class {
	#name : #SoilQueueSettings,
	#superclass : #Object,
	#instVars : [
		'workerLimit',
		'rateLimit',
		'ratePeriod',
		'failureRetryLimit',
		'orphanedRetryLimit',
		'backoffBase',
		'backoffCap'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueSettings class >> from: aDescription [

	^ self new
		setFrom: aDescription;
		yourself
]

{ #category : #retrying }
SoilQueueSettings >> allowsFailureRetryOf: anEntry [
	"whether an entry whose work unit failed retriably may be tried once more. With a limit
	of three, three retries happen and the fourth failure is the one that gives up"

	^ anEntry failureRetries < failureRetryLimit
]

{ #category : #retrying }
SoilQueueSettings >> allowsOrphanedRetryOf: anEntry [
	"whether an entry that lost its worker may be given back once more. Counted like the
	restarts of a resident: with a limit of two, two orphaned entries come back and the
	third orphaning is the one that parks it"

	^ orphanedRetryLimit isNil or: [ anEntry orphanedRetries < orphanedRetryLimit ]
]

{ #category : #rate }
SoilQueueSettings >> rateLimit [
	"how many entries may go out in any period of #ratePeriod, or nil for no rate"

	^ rateLimit
]

{ #category : #rate }
SoilQueueSettings >> ratePeriod [

	^ ratePeriod
]

{ #category : #retrying }
SoilQueueSettings >> retryDelayAfter: anInteger [
	"the pause before retry number anInteger: the base, doubled for every failure before
	it, never longer than the cap"

	^ (backoffBase * (2 raisedTo: anInteger - 1)) min: backoffCap
]

{ #category : #initialization }
SoilQueueSettings >> setFrom: aDescription [
	"the values as the description answers them, defaults included, so that I need not
	know what the defaults are"

	workerLimit := aDescription workerLimit.
	rateLimit := aDescription rateLimit.
	ratePeriod := aDescription ratePeriod.
	failureRetryLimit := aDescription failureRetryLimit.
	orphanedRetryLimit := aDescription orphanedRetryLimit.
	backoffBase := aDescription backoffBase.
	backoffCap := aDescription backoffCap
]

{ #category : #accessing }
SoilQueueSettings >> workerLimit [

	^ workerLimit
]
