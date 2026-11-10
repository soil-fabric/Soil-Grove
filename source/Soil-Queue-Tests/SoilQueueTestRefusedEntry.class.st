"
An entry whose far side refuses every call: my work unit notes the call on my target and
answers #retry. Nothing is wrong with the work, it just did not go through, so I am given
back the way an orphan is and parked when my lane allows no more.

The note on the target is there to show that nothing of a step that did not go through is
kept: it goes with the transaction.
"
Class {
	#name : #SoilQueueTestRefusedEntry,
	#superclass : #SoilQueueEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestRefusedEntry >> performIn: aTransaction [

	self target addEffect: #called.
	^ #retry
]

{ #category : #working }
SoilQueueTestRefusedEntry >> resumeAfterAbortIn: aTransaction [
	"repeating: a call that was refused changed nothing on the far side. Nothing to put
	right"
]
