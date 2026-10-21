"
An entry whose work unit always fails at its work, with an error of its own. That is a
result, so the first failure is the last: no retry that nobody thought through. It notes
being given up on, on its target.
"
Class {
	#name : #SoilQueueTestBrokenEntry,
	#superclass : #SoilQueueTestEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestBrokenEntry >> giveUp: anError in: aTransaction [

	self target addEffect: { #gaveUp. anError messageText. self orphanedRetries }
]

{ #category : #working }
SoilQueueTestBrokenEntry >> performIn: aTransaction [

	^ self error: 'the far side refused the request'
]
