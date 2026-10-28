"
An entry whose work unit fails at its work, and whose giving up is raced: the queue books
the failure in a transaction of its own (SoilQueue>>#book:for:), outside the run-again of a
conflict, and before that transaction commits another one writes the same target. The
booking meets a write conflict at its commit, and the conflict gets out of the step.
"
Class {
	#name : #SoilQueueTestRacedGivingUpEntry,
	#superclass : #SoilQueueTestRacedEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestRacedGivingUpEntry >> giveUp: anError in: aTransaction [

	self target addEffect: #gaveUp.
	self raceFor: aTransaction
]

{ #category : #working }
SoilQueueTestRacedGivingUpEntry >> performIn: aTransaction [

	^ self error: 'the far side refused the request'
]
