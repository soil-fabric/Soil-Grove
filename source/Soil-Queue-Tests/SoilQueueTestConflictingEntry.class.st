"
An entry whose work runs into a write conflict a fixed number of times before it goes
through.

A real conflict arises at commit, when somebody else wrote the same objects first, and
producing one on purpose takes two transactions racing each other. The failure is the
same either way, and what is worth testing is what the queue does about it -- so I raise
it directly and say so.

Both counters are on my class, and that is not laziness. A conflict discards the whole
transaction, so everything the entry noted in it goes with it: after the retry my
instance is read again from disk, exactly as it was before the attempt. That re-read is
the entire point of starting over rather than committing again, and a counter on the
instance would be reset by it and conflict for ever. The attempts happened in the image,
so the image is where they are counted.
"
Class {
	#name : #SoilQueueTestConflictingEntry,
	#superclass : #SoilQueueEntry,
	#classVars : [
		'Attempts',
		'ConflictsToRaise'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #accessing }
SoilQueueTestConflictingEntry class >> attempts [
	"how often a work unit of mine actually ran"

	^ Attempts ifNil: [ 0 ]
]

{ #category : #accessing }
SoilQueueTestConflictingEntry class >> conflictsToRaise: anInteger [

	Attempts := 0.
	ConflictsToRaise := anInteger
]

{ #category : #accessing }
SoilQueueTestConflictingEntry class >> resumption [

	^ #repeating
]

{ #category : #working }
SoilQueueTestConflictingEntry >> performIn: aTransaction [

	Attempts := self class attempts + 1.
	self target addEffect: #attempt.
	(ConflictsToRaise ifNil: [ 0 ]) > 0 ifTrue: [
		ConflictsToRaise := ConflictsToRaise - 1.
		SoilObjectHasConcurrentChange new signal ].
	^ #finished
]
