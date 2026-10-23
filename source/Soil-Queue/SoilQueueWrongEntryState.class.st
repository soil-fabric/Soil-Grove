"
I am raised when an entry is asked for a transition its current state does not allow --
claiming one that is claimed already, giving back one that nobody claimed.

I exist rather than a silent no-op because both transitions mark a boundary in the crash
story: a second claim on the same entry means two workers hold it, and giving back an
unclaimed entry means somebody believes they held what nobody took. Both are
programming errors in the caller, and both are invisible afterwards if the transition
just does nothing.

I carry the entry. An entry has two states, so the one that was expected is the other
one, and the entry says which it is.
"
Class {
	#name : #SoilQueueWrongEntryState,
	#superclass : #Error,
	#instVars : [
		'entry'
	],
	#category : #'Soil-Queue'
}

{ #category : #signalling }
SoilQueueWrongEntryState class >> signalFor: anEntry [

	^ self new
		entry: anEntry;
		signal
]

{ #category : #accessing }
SoilQueueWrongEntryState >> entry [

	^ entry
]

{ #category : #accessing }
SoilQueueWrongEntryState >> entry: anEntry [

	entry := anEntry
]

{ #category : #accessing }
SoilQueueWrongEntryState >> messageText [

	^ messageText ifNil: [
		entry class name , ' is ' , entry state asString , ', which does not allow this' ]
]
