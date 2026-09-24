"
An entry whose work unit fails the way a far side that answers 503 fails: for a while,
and retriably. It fails as long as it has been retried fewer times than it was told to
fail, then it works.

The count it goes by is #failureRetries and nothing of its own. A counter kept here would
be rolled back with the transaction of the work unit that threw -- the queue's
bookkeeping is the only thing about a failed attempt that is committed.

When it is given up on, it writes that on its target, with the two counters as they
stood: a given-up entry leaves the ordering, and the target is where a test can still
read what happened.
"
Class {
	#name : #SoilQueueTestFlakyEntry,
	#superclass : #SoilQueueTestEntry,
	#instVars : [
		'failures'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestFlakyEntry class >> on: aTarget failing: anInteger [

	^ (self on: aTarget)
		setFailures: anInteger;
		yourself
]

{ #category : #working }
SoilQueueTestFlakyEntry >> classifyError: anError [

	^ #retriable
]

{ #category : #working }
SoilQueueTestFlakyEntry >> giveUp: anError in: aTransaction [

	self target addEffect: { #gaveUp. anError messageText. self failureRetries. self orphanedRetries }
]

{ #category : #working }
SoilQueueTestFlakyEntry >> performIn: aTransaction [

	self failureRetries < failures ifTrue: [ ^ self error: 'the far side answered 503' ].
	self target addEffect: #ran.
	^ #finished
]

{ #category : #initialization }
SoilQueueTestFlakyEntry >> setFailures: anInteger [

	failures := anInteger
]
