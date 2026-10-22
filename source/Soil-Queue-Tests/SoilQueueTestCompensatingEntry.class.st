"
The third resumption semantics, the one that gets forgotten: I cannot simply be run
again, because an aborted attempt leaves something behind that has to go first.

My cleanup takes the last effect off my target and notes how many it found there. A test
can then see both that it ran and that it ran *before* the fresh attempt.
"
Class {
	#name : #SoilQueueTestCompensatingEntry,
	#superclass : #SoilQueueEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestCompensatingEntry >> performIn: aTransaction [

	self target addEffect: #ran.
	^ #finished
]

{ #category : #working }
SoilQueueTestCompensatingEntry >> resumeAfterAbortIn: aTransaction [
	"compensating: the aborted attempt may have left its effect on my target, and that goes
	before I run again"

	self target undoLastEffect
]
