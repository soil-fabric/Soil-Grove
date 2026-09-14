"
I am raised when an entry is asked for a transition its current state does not allow --
claiming one that is not pending, finishing one that was never claimed.

I exist rather than a silent no-op because every one of those transitions marks a
boundary in the crash story: a second claim on the same entry means two workers hold
it, and a #markDone on an unclaimed entry means work was counted that nobody took.
Both are programming errors in the caller, and both are invisible afterwards if the
transition just does nothing.

I carry the entry and the state that was expected, so the report says which of the two
went wrong without the reader having to guess from a message text.
"
Class {
	#name : #SoilQueueWrongEntryState,
	#superclass : #Error,
	#instVars : [
		'entry',
		'expectedState'
	],
	#category : #'Soil-Queue'
}

{ #category : #signalling }
SoilQueueWrongEntryState class >> signalFor: anEntry expecting: aSymbol [

	^ self new
		entry: anEntry;
		expectedState: aSymbol;
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
SoilQueueWrongEntryState >> expectedState [

	^ expectedState
]

{ #category : #accessing }
SoilQueueWrongEntryState >> expectedState: aSymbol [

	expectedState := aSymbol
]

{ #category : #accessing }
SoilQueueWrongEntryState >> messageText [

	^ messageText ifNil: [
		'expected a ' , expectedState asString , ' entry, but ' , entry printString
			, ' is ' , entry state asString ]
]
