"
An entry whose target the queue cannot get to: reading it fails with an error of Soil's.

I stand in for the real cases -- a wrapper that reads but points at nothing, a target
whose cluster is no longer there, a segment that is not there yet. Those are hard to
produce on purpose without breaking a database, so I raise the error directly. What is
tested through me is what the queue does about it, which is the part that has to be
right: it is no statement about my work, so I am not given up on but given back, after a
wait, and parked when my lane allows no more.
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

{ #category : #working }
SoilQueueTestUnreachableEntry >> performIn: aTransaction [

	^ SoilError signal: 'the record of the target cannot be read'
]
