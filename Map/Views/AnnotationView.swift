//
//  AnnotationView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import MapKit
import UIKit

class AnnotationView: MKMarkerAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        updateView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var annotation: MKAnnotation? {
        didSet {
            updateView()
        }
    }
    
    // UpdateView Function
    private func updateView() {
        guard let annotation = annotation else { return }
        if annotation is Annotation {
            clusteringIdentifier = "element"
        } else if let cluster = annotation as? MKClusterAnnotation {
            clusteringIdentifier = nil
            displayPriority = .defaultHigh
            let totalCount = cluster.memberAnnotations.count
            markerTintColor = UIColor(named: "MarkerColor")
            glyphText = "\(totalCount)"
        }
        canShowCallout = true
    }
}
