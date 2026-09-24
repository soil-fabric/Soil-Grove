"
An entry whose work unit always throws and which leaves the classification to the base.
The base says #permanent, so the first failure is the last: no retry that nobody thought
through. It notes being given up on, on its target, like the flaky one.
"
Class {
	#name : #SoilQueueTestBrokenEntry,
	#superclass : #SoilQueueTestEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestBrokenEntry >> giveUp: anError in: aTransaction [

	self target addEffect: { #gaveUp. anError messageText. self failureRetries. self orphanedRetries }
]

{ #category : #working }
SoilQueueTestBrokenEntry >> performIn: aTransaction [

	^ self error: 'the far side refused the request'
]
