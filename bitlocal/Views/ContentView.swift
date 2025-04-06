// ContentView.swift

import UIKit
import SwiftUI
import MapKit
import CoreLocationUI
import Combine

@available(iOS 16.4, *) 
struct ContentView: View {
    
    @StateObject private var viewModel = ContentViewModel()
    
    @State public var showingAbout = false
    @State public var elements: [Element]?
    @State public var visibleElements: [Element] = []
    
    @State private var userLocation: CLLocation?
    @State private var cancellable: Cancellable?
    @State private var mapStoppedMovingCancellable: Cancellable?
    @State private var cancellableUserLocation: Cancellable?
    @State private var firstLocationUpdate: Bool = true
    @State private var headerHeight: CGFloat = 0
    @State private var showingSettings = false
    
    // Appearance from @AppStorage
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("selectedMapType") private var storedMapType: Int = 0
    
    let appName = "BitLocal"
    let apiManager = APIManager()
    
    var selectedMapTypeBinding: Binding<MKMapType> {
        Binding<MKMapType>(
            get: { MKMapType.from(int: storedMapType) },
            set: { storedMapType = $0.intValue }
        )
    }
    
    // This computed property lets you use "selectedMapType" in read-only contexts:
    var selectedMapType: MKMapType {
        selectedMapTypeBinding.wrappedValue
    }
    
    var body: some View {
        
        // **** Main View ****
        return GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            
            if screenWidth > 768 || screenHeight > 1024 { // iPad layout
                HStack(spacing: 0) {
                    NavigationStack(path: $viewModel.path) {
                        BusinessesListView(elements: visibleElements)
                            .environmentObject(viewModel)
                            .navigationDestination(for: Element.self) { element in
                                BusinessDetailView(
                                    element: element,
                                    userLocation: viewModel.userLocation,
                                    contentViewModel: viewModel)
                                .environmentObject(viewModel)
                            }
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    SettingsButtonView(showingSettings: $showingSettings)
                                        .opacity(0)
                                }
                                ToolbarItem(placement: .principal) {
                                    CustomiPadNavigationStackTitleView()
                                        .frame(maxWidth: .infinity)
                                }
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    InfoButtonView(showingAbout: $showingAbout)
                                }
                            }
                    }
                    .frame(width: calculateSidePanelWidth(screenWidth: screenWidth))
                    .navigationBarTitleDisplayMode(.automatic)
                    
                    ZStack {
                        if let elements = elements {
                            mapView(
                                elements: elements,
                                topPadding: headerHeight,
                                bottomPadding: viewModel.bottomPadding,
                                mapType: selectedMapType
                            )
                            .ignoresSafeArea()
                            .onAppear {
                                viewModel.locationManager.requestWhenInUseAuthorization()
                                viewModel.locationManager.startUpdatingLocation()
                            }
                            .overlay(
                                OpenStreetMapAttributionView()
                                    .padding(.bottom, 7)
                                    .padding(.leading, 100),
                                alignment: .bottomLeading
                            )
                        }
                    }
                    .overlay(
                        mapButtonsView(isIPad: true)
                            .padding(.trailing, 20)
                            .padding(.bottom, 0),
                        alignment: .bottomTrailing
                    )
                }
                .onChange(of: viewModel.path) { newPath in
                    print("iPad onChange handler called")
                    if let selectedElement = newPath.last {
                        viewModel.zoomToElement(selectedElement)
                    } else {
                        // Deselect annotation when the path is empty (i.e., detail view is dismissed)
                        viewModel.deselectAnnotation()
                    }
                    viewModel.selectedElement = newPath.last
                }
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(selectedMapType: selectedMapTypeBinding)
                        .preferredColorScheme(colorSchemeFor(appearance))
                        .id(appearance)
                }
            } else { // iPhone layout
                ZStack {
                    if let elements = elements {
                        mapView(
                            elements: elements,
                            topPadding: headerHeight,
                            bottomPadding: viewModel.bottomPadding,
                            mapType: selectedMapType
                        )
                        .ignoresSafeArea()
                        .onAppear {
                            viewModel.locationManager.requestWhenInUseAuthorization()
                            viewModel.locationManager.startUpdatingLocation()
                        }
                        .overlay(
                            OpenStreetMapAttributionView()
                                .padding(.bottom, geometry.size.height * 0.3 + 1)
                                .padding(.leading, 16),
                            alignment: .bottomLeading
                        )
                    }
                    
                    // Header view
                    VStack {
                        iPhoneHeaderView(screenWidth: geometry.size.width)
                        Spacer()
                    }
                }
                .overlay(
                    mapButtonsView(isIPad: false)
                        .padding(.trailing, 27)
                        .padding(.bottom, geometry.size.height * 0.3 + 10), // 30% of screen height plus an extra 10 points
                    alignment: .bottomTrailing
                )
                .bottomSheet(
                    presentationDetents: [.fraction(0.3), .medium, .large],
                    isPresented: .constant(true),
                    dragIndicator: .visible,
                    sheetCornerRadius: 20,
                    largestUndimmedIdentifier: .medium,
                    interactiveDisabled: true,
                    forcedColorScheme: colorSchemeFor(appearance),
                    content: {
                        BottomSheetContentView(visibleElements: $visibleElements)
                            .id(appearance)
                            .environmentObject(viewModel)
                            .sheet(isPresented: $showingAbout) {
                                AboutView()
                            }
                            .sheet(isPresented: $showingSettings) {
                                SettingsView(selectedMapType: selectedMapTypeBinding)
                                    .preferredColorScheme(colorSchemeFor(appearance))
                                    .id(appearance)
                            }
                            .preferredColorScheme(colorSchemeFor(appearance))
                    },
                    onDismiss: {
                        print("Bottom sheet dismissed")
                    }
                )
                .ignoresSafeArea(.keyboard)
            }
        }
        .onPreferenceChange(HeaderHeightKey.self) { value in
            self.headerHeight = value
            viewModel.topPadding = value
            print("Header Height reported: \(value)")
        }
        .onAppear {
            // Get elements
            apiManager.getElements { elements in
                DispatchQueue.main.async {
                    self.elements = elements
                    viewModel.elements = elements
                }
            }
            // Determine elements visible in user view
            cancellable = viewModel.visibleElementsSubject.sink(receiveValue: { updatedVisibleElements in
                visibleElements = updatedVisibleElements
            })
            // Update user location
            cancellableUserLocation = viewModel.userLocationSubject.sink { updatedUserLocation in
                userLocation = updatedUserLocation
                
                // Zoom in on user's location on the first launch
                if viewModel.initialRegionSet == false {
                    if let coordinate = userLocation?.coordinate {
                        viewModel.centerMap(to: coordinate)
                    }
                }
            }
            // When user stops moving map
            mapStoppedMovingCancellable = viewModel.mapStoppedMovingSubject.sink(receiveValue: {
                // Any additional logic that should be executed when the map stops moving can be added here.
            })
        }
        // Apply the user-chosen color scheme to the entire view hierarchy
        .preferredColorScheme(colorSchemeFor(appearance))
    }
    
    // MARK: - Shared Map Buttons View
    @ViewBuilder
    func mapButtonsView(isIPad: Bool) -> some View {
        VStack(spacing: 10) {
            // Map Type Toggle Button
            Button(action: {
                // Toggle between standard and hybrid
                let newType: MKMapType = (selectedMapTypeBinding.wrappedValue == .standard) ? .hybrid : .standard
                selectedMapTypeBinding.wrappedValue = newType
            }) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 44, height: 44) // Fixed circle size
                        .shadow(radius: 3)
                    Image(systemName: selectedMapType == .standard ? "globe.americas.fill" : "map.fill")
                        .font(.system(size: 20)) // Increase icon size without enlarging the circle
                        .foregroundColor(.white)
                }
            }
            
            // Location Button
            LocationButton(.currentLocation) {
                viewModel.locationManager.requestWhenInUseAuthorization()
                viewModel.isUpdatingLocation = true
                viewModel.locationManager.startUpdatingLocation()
                
                if let coordinate = userLocation?.coordinate {
                    viewModel.centerMap(to: coordinate)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    if viewModel.isUpdatingLocation {
                        let alert = UIAlertController(
                            title: "Location could not be determined. Please check if location permissions have been granted.",
                            message: nil,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            rootViewController.topMostViewController().present(alert, animated: true, completion: nil)
                        }
                        
                        viewModel.locationManager.stopUpdatingLocation()
                        viewModel.isUpdatingLocation = false
                    }
                }
            }
            .tint(.orange)
            .foregroundColor(.white)
            .cornerRadius(20, antialiased: true)
            .labelStyle(.iconOnly)
            .symbolVariant(.fill)
            .shadow(radius: 3)
            //            .overlay(
            //                Group {
            //                    if viewModel.isUpdatingLocation {
            //                        ProgressView()
            //                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            //                            .frame(width: 20, height: 20)
            //                    }
            //                }
            //            )
        }
    }
    
    // Helper to map Appearance -> SwiftUI ColorScheme?
    private func colorSchemeFor(_ appearance: Appearance) -> ColorScheme? {
        switch appearance {
        case .system: return nil    // Follows device setting
        case .light:  return .light
        case .dark:   return .dark
        }
    }
    
    private func calculateSidePanelWidth(screenWidth: CGFloat) -> CGFloat {
        // iPad Mini in portrait mode has a width of 744 points
        if screenWidth <= 744 {
            return screenWidth * 0.4 // 40% of screen width for iPad Mini
        } else {
            return screenWidth * 0.35 // 30% for other iPads
        }
    }
    
    // iPhone Header
    func iPhoneHeaderView(screenWidth: CGFloat) -> some View {
        ZStack {
            
            GeometryReader { geometry in
                let height = geometry.size.height * 0.15 // Proportional header height
                
                Rectangle()
                    .cornerRadius(10)
                    .foregroundColor(Color(UIColor.systemBackground)) // Adaptive to light/dark mode
                    .opacity(1)
                    .frame(width: screenWidth, height: height)
                    .padding(.top, -10)
                    .ignoresSafeArea() // Extend into safe area
                    .onAppear {
                        // Accurately capture and update header height
                        DispatchQueue.main.async {
                            viewModel.topPadding = height
                            print("Header Height Updated: \(height)")
                        }
                    }
            }
            
            VStack(alignment: .leading) {
                // BitLocal text and Info Button
                HStack {
                    
                    SettingsButtonView(showingSettings: $showingSettings)
                        .frame(maxWidth: 1, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 5)
                        .allowsHitTesting(false) // Disable interaction
                        .opacity(0) // Make it invisible
                    
                    Spacer()
                    
                    HStack(spacing: 0) {
                        Text(" bit")
                            .font(.custom("Ubuntu-LightItalic", size: 28))
                            .foregroundColor(.orange)
                        
                        Text("local ")
                            .font(.custom("Ubuntu-MediumItalic", size: 28))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    
                    // Info Button
                    InfoButtonView(showingAbout: $showingAbout)
                        .frame(maxWidth: 1, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 2)
                        .padding(.leading, 7)
                }
                .padding(.horizontal)
                .frame(height: 1) // Adjust based on content
                Spacer()
            }
            .padding(.top, 20)
        }
    }
    
    // Navigation Stack Title View for iPad
    struct CustomiPadNavigationStackTitleView: View {
        var body: some View {
            HStack(spacing: 0) {
                Text("bit")
                    .font(.custom("Ubuntu-LightItalic", size: 32))
                    .foregroundColor(.orange)
                
                Text("local")
                    .font(.custom("Ubuntu-MediumItalic", size: 32))
                    .foregroundColor(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(x: -8) // Fine-tune the centering to account for the info button width
        }
    }
    
    struct InfoButtonView: View {
        @Binding var showingAbout: Bool
        
        var body: some View {
            Button(action: {
                showingAbout.toggle()
            }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18)) // Consistent size
                    .foregroundColor(.orange)
            }
            .frame(width: 44) // Fixed width to ensure consistent spacing
            .offset(x: -7, y: +2) // Fine-tune the centering to account for the info button width
        }
    }
    
    struct OpenStreetMapAttributionView: View {
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.colorScheme) var colorScheme
        @State private var isFaded = false
        
        var body: some View {
            Button(action: {
                if let url = URL(string: "https://www.openstreetmap.org/copyright") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Map data from ")
                    .font(.system(size: 10))
                    .foregroundColor(colorScheme == .light ? Color.black : Color.white)
                +
                Text("OpenStreetMap")
                    .font(.system(size: 10))
                    .underline()
                    .foregroundColor(colorScheme == .light ? Color.black : Color.white)
            }
            .padding(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
            .background(Color(colorScheme == .light ? UIColor.white : UIColor.black).opacity(colorScheme == .light ? 0.6 : 0.4))
            .cornerRadius(3)
            .opacity(isFaded ? 0 : 1)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    withAnimation(.easeInOut(duration: 3)) {
                        isFaded = true
                    }
                }
            }
            .onChange(of: scenePhase) { newScenePhase in
                if newScenePhase == .active {
                    withAnimation(.easeInOut(duration: 0)) {
                        isFaded = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        withAnimation(.easeInOut(duration: 3)) {
                            isFaded = true
                        }
                    }
                }
            }
        }
    }
    
    struct BottomSheetContentView: View {
        @EnvironmentObject var viewModel: ContentViewModel
        @Binding var visibleElements: [Element]
        
        var body: some View {
            GeometryReader { geometry in
                VStack {
                    NavigationStack(path: $viewModel.path) {
                        BusinessesListView(elements: visibleElements)
                            .environmentObject(viewModel)
                            .navigationDestination(for: Element.self) { element in
                                BusinessDetailView(
                                    element: element,
                                    userLocation: viewModel.userLocation,
                                    contentViewModel: viewModel
                                )
                            }
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .onAppear {
                    DispatchQueue.main.async {
                        let bottomSheetHeight = geometry.size.height
                        if viewModel.bottomPadding != bottomSheetHeight {
                            viewModel.bottomPadding = bottomSheetHeight
                            print("Accurate Bottom Sheet Height: \(bottomSheetHeight)")
                        }
                    }
                }
                .onChange(of: geometry.size.height) { newHeight in
                    viewModel.bottomPadding = newHeight
                    print("BottomSheetContentView height updated: \(newHeight)")
                }
                .onChange(of: viewModel.path) { newPath in
                    print("BottomSheet path changed (iPhone scenario)")
                    if let selectedElement = newPath.last {
                        // If detail view is pushed, zoom to element
                        viewModel.zoomToElement(selectedElement)
                    } else {
                        // If no element is selected (path is empty), deselect annotation
                        viewModel.deselectAnnotation()
                    }
                }
            }
        }
    }
    
    func mapView(elements: [Element], topPadding: CGFloat, bottomPadding: CGFloat, mapType: MKMapType) -> some View {
        MapView(elements: $elements, topPadding: topPadding, bottomPadding: bottomPadding, mapType: mapType)
            .environmentObject(viewModel)
    }
    
    struct MapView: UIViewRepresentable {
        @Binding var elements: [Element]?
        @EnvironmentObject var viewModel: ContentViewModel
        
        // Properties for Dynamic Padding
        var topPadding: CGFloat
        var bottomPadding: CGFloat
        
        // Propery for map type selection
        var mapType: MKMapType
        
        // Initializer
        init(elements: Binding<[Element]?>, topPadding: CGFloat, bottomPadding: CGFloat, mapType: MKMapType) {
            self._elements = elements
            self.topPadding = topPadding
            self.bottomPadding = bottomPadding
            self.mapType = mapType
        }
        
        // Create the Coordinator, which will act as the MKMapViewDelegate
        func makeCoordinator() -> Coordinator {
            Coordinator(viewModel: viewModel, topPadding: topPadding, bottomPadding: bottomPadding)
        }
        
        // Create and configure the MKMapView
        func makeUIView(context: Context) -> MKMapView {
            let mapView = MKMapView()
            
            // Store reference to mapView in viewModel
            viewModel.mapView = mapView
            
            // Set the delegate to the Coordinator
            mapView.delegate = context.coordinator
            
            // Set up clustering
            setupCluster(mapView: mapView)
            
            // Show user location on the map
            mapView.showsUserLocation = true
            
            // Set initial map type
            mapView.mapType = mapType
            
            return mapView
        }
        
        // Update the MKMapView when the SwiftUI view updates
        func updateUIView(_ mapView: MKMapView, context: Context) {
            // Update padding in Coordinator
            context.coordinator.updatePadding(top: topPadding, bottom: bottomPadding)
            
            if mapView.mapType != mapType {
                mapView.mapType = mapType
            }
            
            // Handle updating annotations if `elements` change
            context.coordinator.updateAnnotations(mapView: mapView, elements: elements)
        }
        
        // Set up clustering for map annotations
        private func setupCluster(mapView: MKMapView) {
            let clusteringIdentifier = "Cluster"
            mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: clusteringIdentifier)
        }
        
        // Coordinator class to handle MKMapViewDelegate methods and annotations management
        class Coordinator: NSObject, MKMapViewDelegate {
            var viewModel: ContentViewModel
            var topPadding: CGFloat
            var bottomPadding: CGFloat
            var mapRegionChangeCompletion: (() -> Void)?
            
            // Keep track of previously displayed elements to manage annotations efficiently
            var previousElements: Set<Element> = []
            var currentAnnotations: [String: Annotation] = [:] // Keep track of current annotations
            private var cancellable: AnyCancellable?
            private var debounceTimer: AnyCancellable?
            
            init(viewModel: ContentViewModel, topPadding: CGFloat, bottomPadding: CGFloat) {
                self.viewModel = viewModel
                self.topPadding = topPadding
                self.bottomPadding = bottomPadding
            }
            
            // Update padding method
            func updatePadding(top: CGFloat, bottom: CGFloat) {
                self.topPadding = top
                self.bottomPadding = bottom
            }
            
            // Smoothly expand the cluster and zoom to a specific annotation
            private func expandClusterAndZoomToAnnotation(_ cluster: MKClusterAnnotation, targetAnnotation: MKAnnotation, mapView: MKMapView) {
                // Calculate the bounding rect for the cluster's member annotations
                var rect = MKMapRect.null
                for annotation in cluster.memberAnnotations {
                    let point = MKMapPoint(annotation.coordinate)
                    rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                }
                
                // Apply a slight zoom-out scale for better visual feedback
                let zoomOutScale: Double = 1.3
                rect = rect.insetBy(dx: -rect.size.width * (zoomOutScale - 1), dy: -rect.size.height * (zoomOutScale - 1))
                
                // Edge padding for header and bottom sheet
                let edgePadding = UIEdgeInsets(
                    top: viewModel.topPadding + 10,
                    left: 20,
                    bottom: viewModel.bottomPadding + 100,
                    right: 20
                )
                
                // Smoothly animate to the expanded cluster region
                DispatchQueue.main.async {
                    UIView.animate(withDuration: 0.7, delay: 0, options: [.curveEaseInOut], animations: {
                        mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: false)
                    }, completion: { _ in
                        // After cluster expansion, smoothly center and zoom into the target annotation
                        self.centerAnnotationSmoothly(mapView: mapView, annotation: targetAnnotation)
                    })
                }
            }
            
            // Smoothly center and zoom into an annotation
            private func centerAnnotationSmoothly(mapView: MKMapView, annotation: MKAnnotation) {
                let targetCoordinate = annotation.coordinate
                
                // Desired camera altitude for zoom (adjust this value for more/less zoom)
                let altitude: CLLocationDistance = 500 // A lower value zooms in more
                
                // Create an MKMapCamera with the target coordinate and altitude
                let camera = MKMapCamera(lookingAtCenter: targetCoordinate, fromDistance: altitude, pitch: 0, heading: 0)
                
                // Perform a smooth camera animation
                UIView.animate(withDuration: 1.0, delay: 0, options: [.curveEaseInOut], animations: {
                    mapView.setCamera(camera, animated: true)
                }, completion: { _ in
                    // Select the annotation after the animation completes
                    DispatchQueue.main.async {
                        mapView.selectAnnotation(annotation, animated: true)
                    }
                })
            }
            
            // Ensure to cancel the subscription when the Coordinator is deinitialized
            deinit {
                cancellable?.cancel()
            }
            
            // Efficiently update annotations by only adding/removing what's changed
            func updateAnnotations(mapView: MKMapView, elements: [Element]?) {
                guard let elements = elements else { return }
                
                let visibleRect = mapView.visibleMapRect
                let centerCoordinate = mapView.centerCoordinate
                let centerLocation = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
                
                let visibleElements = elements.filter { element in
                    guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else { return false }
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let location = CLLocation(latitude: lat, longitude: lon)
                    let distance = location.distance(from: centerLocation)
                    
                    let mapPoint = MKMapPoint(coordinate)
                    return visibleRect.contains(mapPoint) &&
                    distance <= 25 * 1609.344 && // 25 miles in meters
                    (element.deletedAt == nil || element.deletedAt == "") &&
                    (element.osmJSON?.tags?.name != nil || element.osmJSON?.tags?.operator != nil)
                }
                
                let existingAnnotations = mapView.annotations.compactMap { $0 as? Annotation }
                let existingElements = Set(existingAnnotations.compactMap { $0.element })
                let newElements = Set(visibleElements)
                
                let annotationsToRemove = existingAnnotations.filter { !newElements.contains($0.element!) }
                let elementsToAdd = newElements.subtracting(existingElements)
                
                mapView.removeAnnotations(annotationsToRemove)
                
                let newAnnotations = elementsToAdd.map { Annotation(element: $0) }
                mapView.addAnnotations(newAnnotations)
                
                // Update visible elements
                self.viewModel.visibleElementsSubject.send(Array(newElements))
            }
            
            // MARK: - MKMapViewDelegate Methods
            
            func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
                let reuseIdentifier = "AnnotationView"
                var view: MKMarkerAnnotationView?
                
                if let cluster = annotation as? MKClusterAnnotation {
                    // Handle cluster annotations
                    view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
                    view?.clusteringIdentifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
                    view?.markerTintColor = .orange
                    view?.glyphText = "\(cluster.memberAnnotations.count)"
                } else if let annotation = annotation as? Annotation {
                    // Handle individual annotations
                    if annotation.element == nil {
                        fatalError("Failed to get element from annotation.")
                    }
                    view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
                    view?.clusteringIdentifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
                    view?.canShowCallout = true
                    view?.markerTintColor = .orange
                    view?.glyphText = nil
                    view?.glyphTintColor = .white
                    view?.glyphImage = UIImage(systemName: "location.circle.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                    view?.displayPriority = .required
                }
                return view
            }
            
            // Handle annotation selection to update navigation path
            func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
                if let cluster = view.annotation as? MKClusterAnnotation {
                    let annotations = cluster.memberAnnotations
                    
                    // Calculate the bounding map rect for the cluster annotations
                    var rect = MKMapRect.null
                    for annotation in annotations {
                        let point = MKMapPoint(annotation.coordinate)
                        rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                    }
                    
                    // Apply a scale factor to control zoom level
                    let zoomOutScale: Double = 1.3 // Adjust this value for better zoom
                    rect = rect.insetBy(dx: -rect.size.width * (zoomOutScale - 1),
                                        dy: -rect.size.height * (zoomOutScale - 1))
                    
                    // Edge padding to respect header and bottom sheet
                    let topInset: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 10 : viewModel.topPadding + 10
                    let edgePadding = UIEdgeInsets(
                        top: topInset,
                        left: 20,
                        bottom: viewModel.bottomPadding + 100,
                        right: 20
                    )
                    
                    // Set the visible map rect with padding and zoom adjustments
                    mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: true)
                    
                    print("""
                    Cluster Selected -> 
                    Edge Padding (Top: \(edgePadding.top), Bottom: \(edgePadding.bottom)),
                    Zoom Scale: \(zoomOutScale)
                    """)
                }
                else if let annotation = view.annotation as? Annotation, let element = annotation.element {
                    // Restore the logic to display BusinessDetailView
                    DispatchQueue.main.async {
                        self.viewModel.path = [element] // Update path for NavigationStack
                        self.viewModel.selectedElement = element // Update the selected element
                        
                        print("Annotation tapped: \(element)")
                    }
                }
            }
            
            
            // Detect when the map region changes
            func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
                // Update the view model's region to match the map's region
                self.viewModel.updateMapRegion(center: mapView.region.center, span: mapView.region.span)
                
                // Debounce the call to update annotations
                debounceTimer?.cancel()
                debounceTimer = Just(())
                    .delay(for: .seconds(0.5), scheduler: RunLoop.main)
                    .sink { [weak self] _ in
                        guard let self = self else { return }
                        self.updateAnnotations(mapView: mapView, elements: self.viewModel.elements)
                    }
                
                if animated, let completion = mapRegionChangeCompletion {
                    // Trigger completion handler
                    mapRegionChangeCompletion = nil // Reset to avoid repeated calls
                    completion()
                }
            }
            
            // Update visible elements based on annotations in the visible map rect
            func updateVisibleElements(for mapView: MKMapView) {
                let visibleAnnotations = mapView.annotations(in: mapView.visibleMapRect)
                let visibleElements = visibleAnnotations.compactMap { ($0 as? Annotation)?.element }
                
                self.viewModel.visibleElementsSubject.send(visibleElements)
                self.viewModel.mapStoppedMovingSubject.send(())
            }
        }
    }
}


// ContentViewModel
@available(iOS 16.4, *)
final class ContentViewModel: NSObject, ObservableObject, CLLocationManagerDelegate, MKMapViewDelegate {
    // Sets the initial state of the map before getting user location. Coordinates are for Nashville, TN.
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.13, longitude: -86.775), span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
    @Published var userLocation: CLLocation?
    @Published var isUpdatingLocation = false
    @Published var geocodingCache = LRUCache<String, Address>(maxSize: 100)
    @Published var path: [Element] = []
    @Published var selectedElement: Element?
    @Published var cellViewModels: [String: ElementCellViewModel] = [:]
    @Published var elements: [Element]? = []
    @Published var topPadding: CGFloat = 0
    @Published var bottomPadding: CGFloat = 0
    @Published var initialRegionSet = false // Track if initial region has been set
    
    let locationManager = CLLocationManager()
    let userLocationSubject = PassthroughSubject<CLLocation?, Never>()
    let visibleElementsSubject = PassthroughSubject<[Element], Never>()
    let mapStoppedMovingSubject = PassthroughSubject<Void, Never>()
    let geocoder = Geocoder(maxConcurrentRequests: 5)
    let centerMapToCoordinateSubject = PassthroughSubject<CLLocationCoordinate2D, Never>()     // Publisher to center map to a coordinate
    
    private var cancellables = Set<AnyCancellable>()
    private var debounceTimer: AnyCancellable?
    weak var mapView: MKMapView?
    
    override init() {
        super.init()
        locationManager.delegate = self
        mapView?.delegate = self
        setupCenterMapSubscription()
    }
    
    // Request location
    func requestWhenInUseLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // Get latest location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.first else {
            // TODO: Show an error
            return
        }
        // Update map view to show user location
        DispatchQueue.main.async {
            self.updateMapRegion(center: latestLocation.coordinate)
            self.userLocation = latestLocation
            self.userLocationSubject.send(latestLocation)
        }
        manager.stopUpdatingLocation() // Stop updating location once we have the user's location
        isUpdatingLocation = false    // Set isUpdatingLocation to false so the progress view disappears
    }
    
    // locationManager failure scenario (could not get user location)
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // TODO: Need better error handling
        print(error.localizedDescription)
    }
    
    // Calculate distance between element and user location
    func distanceInMiles(element: Element) -> Double? {
        guard let userLocation = userLocation,
              let lat = element.osmJSON?.lat,
              let lon = element.osmJSON?.lon else {
            return nil
        }
        let location = CLLocation(latitude: lat, longitude: lon)
        let distanceInMeters = userLocation.distance(from: location)
        let distanceInMiles = distanceInMeters / 1609.34
        return distanceInMiles
    }
    
    // Determining distance from center
    func distanceFromCenter(location: CLLocationCoordinate2D) -> CLLocationDistance {
        let centerLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let annotationLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        return centerLocation.distance(from: annotationLocation)
    }
    
    // Zoom to element
    func zoomToElement(_ element: Element) {
        guard let mapView = mapView,
              let lat = element.osmJSON?.lat,
              let lon = element.osmJSON?.lon else { return }
        
        let targetCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let targetCamera = MKMapCamera(
            lookingAtCenter: targetCoordinate,
            fromDistance: 500,
            pitch: 0,
            heading: 0
        )
        
        let inCluster = mapView.annotations
            .compactMap { $0 as? MKClusterAnnotation }
            .contains { cluster in
                cluster.memberAnnotations.contains { member in
                    (member as? Annotation)?.element?.id == element.id
                }
            }
        
        let duration: TimeInterval = 0.5
        let selectionDelay: TimeInterval = inCluster ? 0.8 : 0.1
        
        UIView.animate(
            withDuration: duration,
            animations: {
                mapView.setCamera(targetCamera, animated: false)
            },
            completion: { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                    if let annotation = mapView.annotations.first(where: {
                        ($0 as? Annotation)?.element?.id == element.id
                    }) {
                        mapView.selectAnnotation(annotation, animated: true)
                    }
                }
            }
        )
    }
    
    private func setupCenterMapSubscription() {
        centerMapToCoordinateSubject
            .sink { [weak self] coordinate in
                guard let self = self, let mapView = self.mapView else { return }
                let newZoomLevel = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                let region = MKCoordinateRegion(center: coordinate, span: newZoomLevel)
                let edgePadding = UIEdgeInsets(
                    top: topPadding + 10,
                    left: 20,
                    bottom: bottomPadding + 100,
                    right: 20
                )
                mapView.setCameraBoundary(MKMapView.CameraBoundary(coordinateRegion: region), animated: true)
                mapView.setVisibleMapRect(region.mapRect, edgePadding: edgePadding, animated: true)
            }
            .store(in: &cancellables)
    }
    
    func centerMap(to coordinate: CLLocationCoordinate2D, animated: Bool = true) {
        guard let mapView = mapView else { return }
        
        if !initialRegionSet {
            // Set an initial zoom level only once
            print("Setting initial region -> Coordinate: \(coordinate.latitude), \(coordinate.longitude)")
            let initialRegion = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3) // Default zoom level
            )
            mapView.setRegion(initialRegion, animated: animated)
            initialRegionSet = true
        } else {
            // Preserve zoom level and only center the map
            print("Centering Map -> Coordinate: \(coordinate.latitude), \(coordinate.longitude)")
            mapView.setCenter(coordinate, animated: animated)
        }
    }
    
    // Update map region
    func updateMapRegion(center: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil, animated: Bool = true) {
        let updatedSpan = span ?? region.span
        self.region = MKCoordinateRegion(center: center, span: updatedSpan)
        mapView?.setRegion(self.region, animated: animated)
    }
    
    // Deselect the currently selected annotation
    func deselectAnnotation() {
        selectedElement = nil
        DispatchQueue.main.async {
            self.mapView?.selectedAnnotations.forEach { annotation in
                self.mapView?.deselectAnnotation(annotation, animated: true)
            }
        }
    }
}

// Annotation Class
class Annotation: NSObject, Identifiable, MKAnnotation {
    static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.id == rhs.id
    }
    
    let id = UUID()
    let element: Element?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: element?.osmJSON?.lat ?? 0, longitude: element?.osmJSON?.lon ?? 0)
    }
    
    var title: String? {
        element?.osmJSON?.tags?.name
    }
    
    init(element: Element) {
        self.element = element
    }
}

// AnnotationView Class
class AnnotationView: MKMarkerAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        updateView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var annotation: MKAnnotation? {
        willSet {
            updateView()
        }
    }
    
    // UpdateView Function
    private func updateView() {
        guard let annotation = annotation else { return }
        if let _ = annotation as? Annotation {
            clusteringIdentifier = "element"
        } else if let cluster = annotation as? MKClusterAnnotation {
            clusteringIdentifier = nil
            displayPriority = .defaultHigh
            let totalCount = cluster.memberAnnotations.count
            markerTintColor = totalCount < 5 ? .orange : totalCount < 10 ? .yellow : .red
            glyphText = "\(totalCount)"
        }
        canShowCallout = true
    }
}
