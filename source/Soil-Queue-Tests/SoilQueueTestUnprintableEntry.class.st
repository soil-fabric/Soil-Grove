"
An entry that cannot be printed, as an entry whose target cannot be read cannot: printing
it throws. Such a target is often the very reason an entry is given back or parked, and
the line that says so must not take the bookkeeping down with it.
"
Class {
	#name : #SoilQueueTestUnprintableEntry,
	#superclass : #SoilQueueTestRepeatingEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #printing }
SoilQueueTestUnprintableEntry >> printOn: aStream [

	self error: 'the record of the target is not there'
]
