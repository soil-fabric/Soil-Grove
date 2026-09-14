"
An entry whose work the queue cannot get to: whatever it needs is gone.

I stand in for the real cases -- a wrapper that reads but points at nothing, a target
whose cluster is no longer there. Those are hard to produce on purpose without breaking a
database, so I say so directly instead. What is tested through me is what the queue does
about it, which is the part that has to be right.

I am not an entry that *fails*. Failing at the work is a result and ends the entry the
ordinary way; I never get as far as my work unit, and saying so is what tells the two
apart.
"
Class {
	#name : #SoilQueueTestUnreachableEntry,
	#superclass : #SoilQueueEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #accessing }
SoilQueueTestUnreachableEntry class >> resumption [

	^ #repeating
]

{ #category : #testing }
SoilQueueTestUnreachableEntry >> isReadyToRunIn: aTransaction [

	^ false
]

{ #category : #working }
SoilQueueTestUnreachableEntry >> performIn: aTransaction [

	self error: 'a dead letter never gets this far'
]
