"
The stored half of a lane: its name, the section of the index its entries lie in, and
the format that orders them. What shapes a key, and nothing else.

I live in the workspace, because whoever opens the queue without a description still
has to find the entries of each lane. How fast a lane runs is configuration and belongs
to the live lane, SoilQueueLane, which the queue builds from me when it starts.

Several lanes share one index. My section is what keeps their entries apart: every key
of mine carries my marker in front, and a scan of mine stops where my section ends.
"
Class {
	#name : #SoilQueueLaneDescription,
	#superclass : #Object,
	#instVars : [
		'name',
		'range',
		'format'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueLaneDescription class >> named: aSymbol range: aSoilPrefixRange format: aFormat [

	^ self new
		setName: aSymbol
		range: aSoilPrefixRange
		format: aFormat
]

{ #category : #accessing }
SoilQueueLaneDescription >> format [

	^ format
]

{ #category : #testing }
SoilQueueLaneDescription >> includesKey: anIndexKey [
	"whether a key lies in my section -- which is how the lane of an entry is found from its
	key alone"

	^ range includesKey: anIndexKey
]

{ #category : #converting }
SoilQueueLaneDescription >> keyFor: anEntry [
	"the chain: my format orders, and my section places the result -- marker first,
	padding last, filling the whole key size.

	No single participant knows the whole key. The entry supplies values and never a key,
	so that two entries of one lane cannot sort by different rules."

	^ range keyWith: (ByteArray streamContents: [ :parts |
		format appendKeyPartsFor: anEntry on: parts ])
]

{ #category : #accessing }
SoilQueueLaneDescription >> name [

	^ name
]

{ #category : #printing }
SoilQueueLaneDescription >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << name << ' ' << range printString
]

{ #category : #accessing }
SoilQueueLaneDescription >> range [
	"the section of the index that is mine: the marker in front of every key, its width,
	and the key size"

	^ range
]

{ #category : #initialization }
SoilQueueLaneDescription >> setName: aSymbol range: aSoilPrefixRange format: aFormat [

	name := aSymbol.
	range := aSoilPrefixRange.
	format := aFormat
]
