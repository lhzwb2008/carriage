#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
运输费用预测系统 - Web版
"""

from flask import Flask, render_template, jsonify, request
import pandas as pd
import numpy as np
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import StandardScaler
from geopy.distance import geodesic
from datetime import datetime, date
import json
import os
import warnings
warnings.filterwarnings('ignore')

app = Flask(__name__)

# 今日数据存储文件
TODAY_DATA_FILE = 'today_data.json'

# 城市坐标数据库
# Excel中已有的城市 + 几个典型的测试城市
CITY_COORDINATES = {
    # === Excel中已有数据的城市 ===
    '霍尔果斯': (44.2167, 80.4167),
    '阿拉木图': (43.2220, 76.8512),
    '阿斯塔纳': (51.1694, 71.4491),
    '塔什干': (41.2995, 69.2401),
    '莫斯科': (55.7558, 37.6173),
    '阿塞拜疆': (40.4093, 49.8671),  # 巴库
    
    # === 新增的测试城市（无历史数据，用于预测测试）===
    # 哈萨克斯坦
    '卡拉干达': (49.8047, 73.1094),      # 距霍尔果斯833km，介于阿拉木图和阿斯塔纳之间
    '希姆肯特': (42.3417, 69.5967),      # 距霍尔果斯680km，靠近塔什干
    '阿克托别': (50.2839, 57.1670),      # 距霍尔果斯1650km，西哈萨克斯坦
    
    # 吉尔吉斯斯坦
    '比什凯克': (42.8746, 74.5698),      # 距霍尔果斯495km，较近
    
    # 乌兹别克斯坦
    '撒马尔罕': (39.6542, 66.9597),      # 距霍尔果斯1200km，丝绸之路名城
    
    # 俄罗斯
    '新西伯利亚': (55.0084, 82.9357),    # 距霍尔果斯1214km，西伯利亚
    '叶卡捷琳堡': (56.8389, 60.6057),    # 距霍尔果斯1972km，乌拉尔地区
    
    # 格鲁吉亚
    '第比利斯': (41.7151, 44.8271),      # 距霍尔果斯2894km，高加索地区
}

# Excel中有历史数据的城市
CITIES_WITH_HISTORY = ['阿拉木图', '阿斯塔纳', '塔什干', '莫斯科', '阿塞拜疆']

# 所有可选城市（排除霍尔果斯作为唯一出发地）
ALL_CITIES = list(CITY_COORDINATES.keys())


class Predictor:
    def __init__(self, excel_file):
        self.excel_file = excel_file
        self.df = None
        self.today_data = []
        self.models = {}
        self.scalers = {}
        self.vehicle_types = []
        
    def load_data(self):
        """加载Excel数据和今日手动录入数据"""
        self.df = pd.read_excel(self.excel_file)
        self.today_data = load_today_data()
        return True
    
    def get_distance(self, from_city, to_city):
        """计算两个城市之间的距离"""
        if from_city not in CITY_COORDINATES or to_city not in CITY_COORDINATES:
            return None
        return geodesic(CITY_COORDINATES[from_city], CITY_COORDINATES[to_city]).kilometers
    
    def extract_city(self, text):
        """从文本中提取城市名"""
        if pd.isna(text):
            return None
        text = str(text)
        for city in CITY_COORDINATES.keys():
            if city in text:
                return city
        return None
    
    def prepare_and_train(self, from_city='霍尔果斯'):
        """准备数据并训练模型"""
        training_records = []
        
        # 处理Excel历史数据
        for _, row in self.df.iterrows():
            city = self.extract_city(row['目的地'])
            price = row['纯运费']
            vehicle = row['车型']
            
            if city and not pd.isna(price):
                distance = self.get_distance(from_city, city)
                if distance:
                    training_records.append({
                        'city': city,
                        'distance': distance,
                        'price': float(price),
                        'vehicle': vehicle,
                    })
        
        # 处理今日手动录入的数据（权重3倍）
        for record in self.today_data:
            if record.get('from_city') == from_city:
                to_city = record.get('to_city')
                distance = self.get_distance(from_city, to_city)
                if distance:
                    for _ in range(3):  # 今日数据重复3次
                        training_records.append({
                            'city': to_city,
                            'distance': distance,
                            'price': float(record['price']),
                            'vehicle': record['vehicle'],
                        })
        
        if not training_records:
            return False
        
        train_df = pd.DataFrame(training_records)
        self.vehicle_types = sorted(train_df['vehicle'].unique().tolist())
        
        # 按车型训练模型
        for vehicle in self.vehicle_types:
            vehicle_data = train_df[train_df['vehicle'] == vehicle]
            if len(vehicle_data) >= 3:
                X = vehicle_data[['distance']].values
                y = vehicle_data['price'].values
                
                scaler = StandardScaler()
                X_scaled = scaler.fit_transform(X)
                
                model = LinearRegression()
                model.fit(X_scaled, y)
                
                self.models[vehicle] = model
                self.scalers[vehicle] = scaler
        
        # 通用模型
        X_all = train_df[['distance']].values
        y_all = train_df['price'].values
        
        scaler_all = StandardScaler()
        X_all_scaled = scaler_all.fit_transform(X_all)
        
        model_all = LinearRegression()
        model_all.fit(X_all_scaled, y_all)
        
        self.models['通用'] = model_all
        self.scalers['通用'] = scaler_all
        
        return True
    
    def predict(self, from_city, to_city, vehicle_type='通用'):
        """预测运费"""
        distance = self.get_distance(from_city, to_city)
        if distance is None:
            return None, f"无法计算 {from_city} 到 {to_city} 的距离"
        
        self.prepare_and_train(from_city)
        
        if vehicle_type not in self.models:
            vehicle_type = '通用'
        
        model = self.models[vehicle_type]
        scaler = self.scalers[vehicle_type]
        
        X = np.array([[distance]])
        X_scaled = scaler.transform(X)
        predicted = model.predict(X_scaled)[0]
        
        has_history = to_city in CITIES_WITH_HISTORY
        
        return {
            'from_city': from_city,
            'to_city': to_city,
            'distance': round(distance, 0),
            'price': round(max(predicted, 0), 2),
            'vehicle': vehicle_type,
            'has_history': has_history,
            'is_prediction': not has_history
        }, None


def load_today_data():
    """加载今日手动录入的数据"""
    if not os.path.exists(TODAY_DATA_FILE):
        return []
    try:
        with open(TODAY_DATA_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            today = date.today().isoformat()
            return [d for d in data if d.get('date') == today]
    except:
        return []


def load_all_data():
    """加载所有数据"""
    if not os.path.exists(TODAY_DATA_FILE):
        return []
    try:
        with open(TODAY_DATA_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except:
        return []


def save_all_data(data):
    """保存所有数据"""
    with open(TODAY_DATA_FILE, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def save_today_record(record):
    """保存一条今日录入的记录"""
    data = load_all_data()
    
    # 生成唯一ID
    max_id = max([d.get('id', 0) for d in data], default=0)
    record['date'] = date.today().isoformat()
    record['time'] = datetime.now().strftime('%H:%M:%S')
    record['id'] = max_id + 1
    data.append(record)
    
    save_all_data(data)
    return record


def update_record(record_id, updates):
    """更新一条记录"""
    data = load_all_data()
    
    for i, record in enumerate(data):
        if record.get('id') == record_id:
            # 只更新允许的字段
            for field in ['from_city', 'to_city', 'vehicle', 'price']:
                if field in updates:
                    data[i][field] = updates[field]
            data[i]['updated_time'] = datetime.now().strftime('%H:%M:%S')
            save_all_data(data)
            return data[i]
    
    return None


def delete_record(record_id):
    """删除一条记录"""
    data = load_all_data()
    
    for i, record in enumerate(data):
        if record.get('id') == record_id:
            deleted = data.pop(i)
            save_all_data(data)
            return deleted
    
    return None


# 全局预测器
predictor = None


def init_predictor():
    global predictor
    predictor = Predictor('物流信息表_询价收集表.xlsx')
    predictor.load_data()
    predictor.prepare_and_train()


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/api/predict', methods=['POST'])
def api_predict():
    data = request.json
    from_city = data.get('from_city', '霍尔果斯')
    to_city = data.get('to_city', '')
    vehicle = data.get('vehicle', '通用')
    
    if not to_city:
        return jsonify({'error': '请选择目的地'})
    
    if from_city == to_city:
        return jsonify({'error': '出发地和目的地不能相同'})
    
    init_predictor()
    
    result, error = predictor.predict(from_city, to_city, vehicle)
    if error:
        return jsonify({'error': error})
    
    return jsonify(result)


@app.route('/api/add_record', methods=['POST'])
def api_add_record():
    """添加今日录入记录"""
    data = request.json
    
    required = ['from_city', 'to_city', 'vehicle', 'price']
    for field in required:
        if not data.get(field):
            return jsonify({'error': f'缺少必填字段: {field}'})
    
    try:
        price = float(data['price'])
        if price <= 0:
            return jsonify({'error': '价格必须大于0'})
    except:
        return jsonify({'error': '价格格式不正确'})
    
    record = {
        'from_city': data['from_city'],
        'to_city': data['to_city'],
        'vehicle': data['vehicle'],
        'price': price
    }
    
    saved = save_today_record(record)
    return jsonify({'success': True, 'record': saved})


@app.route('/api/today')
def api_today():
    """获取今日录入的数据"""
    records = load_today_data()
    return jsonify({
        'records': records,
        'count': len(records)
    })


@app.route('/api/record/<int:record_id>', methods=['PUT'])
def api_update_record(record_id):
    """更新一条记录"""
    data = request.json
    
    # 验证价格
    if 'price' in data:
        try:
            price = float(data['price'])
            if price <= 0:
                return jsonify({'error': '价格必须大于0'})
            data['price'] = price
        except:
            return jsonify({'error': '价格格式不正确'})
    
    updated = update_record(record_id, data)
    if updated:
        return jsonify({'success': True, 'record': updated})
    else:
        return jsonify({'error': '记录不存在'}), 404


@app.route('/api/record/<int:record_id>', methods=['DELETE'])
def api_delete_record(record_id):
    """删除一条记录"""
    deleted = delete_record(record_id)
    if deleted:
        return jsonify({'success': True, 'deleted': deleted})
    else:
        return jsonify({'error': '记录不存在'}), 404


@app.route('/api/vehicles')
def api_vehicles():
    """获取车型列表"""
    if predictor is None:
        init_predictor()
    return jsonify(predictor.vehicle_types)


@app.route('/api/cities')
def api_cities():
    """获取城市列表"""
    # 构建城市信息（不预算距离，由前端根据选择动态计算）
    cities = []
    for city in ALL_CITIES:
        cities.append({
            'name': city,
            'has_history': city in CITIES_WITH_HISTORY,
            'is_origin': city == '霍尔果斯',
            'lat': CITY_COORDINATES[city][0],
            'lng': CITY_COORDINATES[city][1]
        })
    
    # 按城市名排序（霍尔果斯排第一）
    cities.sort(key=lambda x: (not x['is_origin'], x['name']))
    
    return jsonify({
        'cities': cities,
        'cities_with_history': CITIES_WITH_HISTORY
    })


@app.route('/api/stats')
def api_stats():
    """获取数据统计"""
    if predictor is None:
        init_predictor()
    
    today_records = load_today_data()
    
    return jsonify({
        'total_excel': len(predictor.df),
        'today_manual': len(today_records),
        'vehicles': len(predictor.vehicle_types),
        'date': str(date.today()),
        'cities_count': len(ALL_CITIES)
    })


if __name__ == '__main__':
    init_predictor()
    app.run(debug=True, host='0.0.0.0', port=3000)
