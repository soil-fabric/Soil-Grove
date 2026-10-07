"
A recording queue whose dispatcher gets workers that cannot be started.
"
Class {
	#name : #SoilQueueTestUnstartableQueue,
	#superclass : #SoilQueueTestRecordingQueue,
	#category : #'Soil-Queue-Tests'
}

{ #category : #running }
SoilQueueTestUnstartableQueue >> workerFor: aLane [

	^ SoilQueueTestUnstartableWorker on: self lane: aLane
]
