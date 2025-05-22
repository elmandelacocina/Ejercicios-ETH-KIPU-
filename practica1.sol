// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//impleStorage
// Contrato que permite almacenar y recuperar un valor entero positivo
contract SimpleStorage {
    // Variable privada para almacenar el valor
    int256 private storedData;

    //Constructor que inicializa storedData en 0
    constructor() {
        storedData = 0;
    }

    // Modificador que restringe el valor a ser positivo (>0)
    // _value Valor ingresado que debe ser mayor que cero
    modifier onlyPositive(int256 _value) {
        require(_value > 0, "El valor debe ser mayor que 0");
        _;
    }

    // Almacena un nuevo valor en storedData
    //Aplica el modificador onlyPositive para validar el valor ingresado
    // _value Valor entero positivo a almacenar
    function setData(int256 _value) public onlyPositive(_value) {
        storedData = _value;
    }

    //Retorna el valor almacenado en storedData

    function getData() public view returns (int256) {
        return storedData;
    }
}