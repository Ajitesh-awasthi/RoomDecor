//
//  CartView.swift
//  Shopping
//
//  Created by Berkay Sancar on 27.07.2024.
//

import SwiftUI

public struct CartView: View {
    
    @StateObject private var viewModel = CartViewModel()
//    @EnvironmentObject private var coordinator: Coordinator
    
    public init() { }
    
    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                VStack {
                    ScrollView(.vertical) {
                        if !viewModel.cartItems.isEmpty {
                            ForEach(viewModel.cartItems, id: \.id) { item in
                                ItemRowView(item: item)
                            }
                        } else {
                            EmptyContentView(title: "Cart is empty.", description: "Add items to your cart to purchase.")
                                .offset(y: proxy.size.height / 3)
                                .onAppear() {
                                    emptyContentOnAppear()
                                }
                        }
                    }
             
                    if !viewModel.cartItems.isEmpty {
                        BottomView(proxy: proxy)
                    }
                }
                .onAppear {
                    viewModel.onAppear()
                }
            }
        }
    }
    
    private func emptyContentOnAppear() {
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//            if viewModel.cartItems.isEmpty { coordinator.pop() }
//        }
    }
}

extension CartView {
    
    @ViewBuilder
    private func ItemRowView(item: CartModel) -> some View {
        HStack {
            AsyncImage(url: .init(string: item.images.first!)!) { image in
                image.resizable()
                    .scaledToFit()
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .foregroundStyle(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "photo")
                        .foregroundStyle(.blue)
                        .font(.system(size: 40))
                }
            }
            .frame(width: 120, height: 120)
            .padding(.leading, 8)
            
            VStack(alignment: .leading) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .padding(.top, 4)
                
                Text("$\(item.price, format: .number.precision(.fractionLength(2)))")
                    .padding(.top, 8)
                    .foregroundColor(.blue)
                    .font(.headline)
            }
            
            Spacer()
            
            CustomStepperView(count: item.count, changedValue: { value in
                viewModel.stepperValueChanged(item: item, count: value)
            })
            .padding()
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .foregroundStyle(Color.white)
                .shadow(color: .blue.opacity(0.08), radius: 4, x: 0, y: 3)
        )
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func BottomView(proxy: GeometryProxy) -> some View {
        VStack {
            VStack {
                Rectangle()
                    .frame(width: proxy.size.width, height: 1)
                    .foregroundStyle(.blue)
                
                HStack {
                    Text("Order total:")
                        .font(.headline)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Text("$\(viewModel.orderTotal, format: .number.precision(.fractionLength(2)))")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                .padding()
            }
      
            Button {
//                coordinator.push(.completeOrder(viewModel.prepareOrder()))
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(width: proxy.size.width, height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .background(Color.white)
        .shadow(color: .blue.opacity(0.12), radius: 6, x: 0, y: -2)
    }
}

//#Preview {
//    CartView()
//        .environmentObject(Coordinator())
//}
