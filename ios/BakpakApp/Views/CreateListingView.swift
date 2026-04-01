import SwiftUI
import PhotosUI

struct CreateListingView: View {
    @State private var title = ""
    @State private var description = ""
    @State private var price = ""
    @State private var gender = "Men's"
    @State private var category = "Tops & Shirts"
    @State private var topType = "T-Shirts"
    @State private var bottomType = "Jeans"
    @State private var size = "M"
    @State private var condition = "Like New"
    @State private var dorm = "Bean Hall"
    @State private var selectedPhotos: [PhotosPickerItem] = []

    let genders = ["Men's", "Women's", "Kids"]
    let categories = ["Tops & Shirts", "Bottoms", "Shoes", "Accessories"]
    let topTypes = ["T-Shirts", "Hoodies", "Sweatshirts", "Sweaters", "Shirts", "Polos", "Blouses", "Croptops", "Tanktops"]
    let bottomTypes = ["Jeans", "Sweatpants", "Pants", "Shorts", "Leggings", "Skirts", "Other"]
    let sizes = ["XS", "S", "M", "L", "XL", "Other"]
    let shoeSizes = ["US 3", "US 3.5", "US 4", "US 4.5", "US 5", "US 5.5", "US 6", "US 6.5", "US 7", "US 7.5", "US 8", "US 8.5", "US 9", "US 9.5", "US 10", "US 10.5", "US 11", "US 11.5", "US 12", "US 12.5", "US 13", "US 13.5", "US 14", "US 14.5", "US 15", "Other"]
    let dorms = ["Bean Hall", "Carson Hall", "Earl Hall", "Global Scholars Hall", "Justice Bean Hall", "Kalapuya Ilihi", "Living Learning Center North", "Living Learning Center South", "Riley Hall", "Tingle Hall", "Unthank Hall", "Yasui Hall"]

    var body: some View {
        Form {
            Section("Photos") {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 5, matching: .images) {
                    Text("Select photos")
                }
            }

            Section("Listing") {
                TextField("Title", text: $title)
                TextField("Description", text: $description, axis: .vertical)
                TextField("Price", text: $price)
                    .keyboardType(.decimalPad)
            }

            Section("Category") {
                Picker("Gender", selection: $gender) { ForEach(genders, id: \.self, content: Text.init) }
                Picker("Category", selection: $category) { ForEach(categories, id: \.self, content: Text.init) }
                if category == "Tops & Shirts" {
                    Picker("Top Type", selection: $topType) { ForEach(topTypes, id: \.self, content: Text.init) }
                } else if category == "Bottoms" {
                    Picker("Bottom Type", selection: $bottomType) { ForEach(bottomTypes, id: \.self, content: Text.init) }
                }
                Picker("Size", selection: $size) {
                    ForEach(category == "Shoes" ? shoeSizes : sizes, id: \.self, content: Text.init)
                }
                Picker("Condition", selection: $condition) {
                    ForEach(["Brand New", "Like New", "Good", "Fair"], id: \.self, content: Text.init)
                }
                Picker("Dorm Hall/Living Residence", selection: $dorm) { ForEach(dorms, id: \.self, content: Text.init) }
            }

            Section {
                Button("Post Listing") {
                    // TODO: multipart upload to /products with selected images and fields.
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.uoGreen)
            }
        }
        .navigationTitle("Create Listing")
    }
}
