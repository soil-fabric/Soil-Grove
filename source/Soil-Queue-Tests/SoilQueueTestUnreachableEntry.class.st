"
An entry whose target the queue cannot get to: reading it fails with an error of Soil's.

I stand in for the real cases -- a wrapper that reads but points at nothing, a target
whose cluster is no longer there, a segment that is not there yet. Those are hard to
produce on purpose without breaking a database, so I raise the error directly. What is
tested through me is what the queue does about it, which is the part that has to be
right: it is no statement about my work, so I am not given up on but given back, after a
wait, and parked when my lane allows no more.

My attempts are counted on my class: the transaction of a failed attempt is gone, and
with it anything I would note on myself.
"
Class {
	#name : #SoilQueueTestUnreachableEntry,
	#superclass : #SoilQueueEntry,
	#classVars : [
		'Attempts'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #accessing }
SoilQueueTestUnreachableEntry class >> attempts [
	"how often a work unit of mine ran since the last reset"

	^ Attempts ifNil: [ 0 ]
]

{ #category : #accessing }
SoilQueueTestUnreachableEntry class >> resetAttempts [

	Attempts := 0
]

{ #category : #accessing }
SoilQueueTestUnreachableEntry class >> resumption [

	^ #repeating
]

{ #category : #working }
SoilQueueTestUnreachableEntry >> performIn: aTransaction [

	Attempts := self class attempts + 1.
	^ SoilError signal: 'the record of the target cannot be read'
]
