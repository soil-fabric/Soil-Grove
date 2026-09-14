"
The format that orders a queue by time: due time first, then the entry's id.

The due time comes first because it is what the queue selects by -- the oldest due entry
is the first key of the section, so finding work is a lookup and not a search. The id
comes second and only to make the key unique, which the index needs before an entry can
be moved to a new due time under backoff.

Time is written as milliseconds since the Unix epoch in eight bytes. Seconds would put
too many entries on one key and leave their order to the id alone; microseconds buy
nothing a queue can use, since a rate at the outlet dwarfs the difference.
"
Class {
	#name : #SoilQueueTimeOrderedKeyFormat,
	#superclass : #SoilQueueKeyFormat,
	#category : #'Soil-Queue'
}

{ #category : #converting }
SoilQueueTimeOrderedKeyFormat >> appendKeyPartsFor: anEntry on: aWriteStream [

	aWriteStream
		nextPutAll: ((self millisecondsOf: anEntry eligibleAt) asByteArrayOfSize: 8);
		nextPutAll: anEntry id
]

{ #category : #converting }
SoilQueueTimeOrderedKeyFormat >> millisecondsOf: aDateAndTime [
	"a due time before 1970 is refused rather than written. #asByteArrayOfSize: drops the
	sign without a word -- -5 comes back as 5 -- so such an entry would sort as though it
	were due that far *after* the epoch instead, and nothing would say so"

	| milliseconds |
	milliseconds := (aDateAndTime - DateAndTime unixEpoch) asMilliSeconds.
	milliseconds < 0 ifTrue: [
		^ self error: 'a due time before 1970 has no place in a key: ' , aDateAndTime printString ].
	^ milliseconds
]
