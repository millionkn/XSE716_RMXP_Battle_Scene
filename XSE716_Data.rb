class<<($xse716_action = Object.new)
#===============================工具函数=======================================
  select_attack_target = lambda do |battler,is_enemy,num=1,same=false|
    return lambda do |target,selected|
      return unless target.exist?
      return if selected.length>=num
      return if selected.include?(target)
      return is_enemy^(target.is_a?(battler.class) or battler.is_a?(target.class))
    end
  end
  block_animation = lambda do |id,targets,fun=lambda{}|
    animation = targets.map{|t|t.animation(id)}
    Action.set{animation.each{|a|a.cencal}}
    loop do
      animation.each do |a|
        a.values(&fun) if a.next.running?
        return unless animation.any?{|a|a.running?}
        Action.pause($scene.api_target_action)
      end
    end
  end
  select_target = lambda do |battler,fun|
    select = battler.select_target(fun)
    Action.set{select.cencal}
    Action.pause($scene.api_target_select) while select.next.running?
    select.values{|*args|return args}
  end
  #由于攻击队友，攻击敌人和正常攻击仅仅只有选取目标过程不同，就直接提到这里了
  attack_function = lambda do |battler,targets|
    #==============使用者动画==================
    block_animation.call(battler.animation1_id,[battler])
    #==============对象动画====================
    block_animation.call(battler.animation2_id,targets,lambda do |frame,sprite|
      #事实上，应该对每种攻击动画单独设定
      #时间不太够，统一设置成
      if frame == 3#第3帧进行
        sprite.battler.attack_effect(battler)#'伤害计算'
        if sprite.battler.damage.is_a?(Numeric)#如果命中，则
          sprite.flash(Color.new(255,255,255),4)#'闪烁'
        end
        #出于兼容考虑，show_damage使用了原版中的方式进行展示
        #问题是，原版展示完毕后会删除battler.damage，所以应放到最后面
        sprite.battler.show_damage
      end
    end)
  end
#===============================技能&物品======================================
  xse716_skills = []
  xse716_skills[57] = lambda do |battler|
    #十字斩
    #第三帧和第六帧分别进行小伤害(结算100号技能)
    #如果敌人含有不死属性('对 不死'属性伤害倍率大于100%)
    #第11帧附加不可闪避，破防的强力一击(结算101号技能)
    return Action.new(lambda do
      cost_sp = false
      Action.set_outer do
        return $scene.target_action_break unless battler.movable?
        (return unless battler.sp>=100) unless cost_sp
      end
      targets = select_target.call(battler,select_attack_target.call(battler,true))
      return if targets.empty?
      Action.pause($scene.target_action_start)
      block_animation.call(1,[battler])
      battler.sp-=100
      cost_sp = true
      block_animation.call(67,targets,lambda do |frame,sprite|
        target = sprite.battler
        if frame == 3 || frame == 6
          target.skill_effect(battler,$data_skills[100])
          return unless target.damage.is_a?(Numeric)
          sprite.flash(Color.new(255,255,255),3)
          target.show_damage
        elsif frame == 11
          return unless target.element_rate(9)>100
          target.skill_effect(battler,$data_skills[101])
          return unless target.damage.is_a?(Numeric)
          sprite.flash(Color.new(255,255,255),3)
          target.show_damage
        end
      end)
    end)
  end
  xse716_skills[61] = lambda do |battler|
    #扫荡
    #第四帧进行伤害结算
    #动画播放至第9帧时，70%概率额外选取一个非重复的目标继续扫荡
    #额外目标每个消耗25sp
    return(Action.new(lambda do
      cost_sp = false
      Action.set_outer do
        return $scene.target_action_break unless battler.movable?
        (return unless battler.sp>=100) unless cost_sp
      end
      targets = select_target.call(battler,select_attack_target.call(battler,true))
      return if targets.empty?
      Action.pause($scene.target_action_start)
      block_animation.call(1,[battler])
      battler.sp-=100
      cost_sp = true
      animations = []
      targets.each{|t|animations.push(t.animation(71))}
      while animations.any?{|a|a.running?}
        animations.each do |a|
          next unless a.next.running?
          a.values do |frame,sprite|
            target = sprite.battler
            if frame == 4
              target.skill_effect(battler,$data_skills[61])
              return unless target.damage.is_a?(Numeric)
              sprite.flash(Color.new(255,255,255),3)
              target.show_damage
            elsif frame == 9
              return unless rand(100)<70
              return if battler.sp<25
              func = select_attack_target.call(battler,true)
              select = battler.select_target(lambda do |t,selected|
                return unless func.call(t,selected)
                return !(targets.include?(t))
              end)
              Action.set{select.cencal;animations.each{|a|a.cencal}}
              while select.next.running?
                break if battler.sp<25
                Action.pause($scene.api_target_select)
              end
              select.values do |*args|
                return if args.empty?
                battler.sp-=25
                args.each{|t|animations.push(t.animation(71))}
                targets.concat(args)
              end
            end
          end
        end
        Action.pause($scene.api_target_action)
      end
    end))
  end
  xse716_items = []
#=========================未定义的技能和物品===============================
  define_method(:skills) do |battler,id|
    return xse716_skills[id].call(battler) if xse716_skills[id]
    return Action.new(lambda do
      cost_sp = false
      sp = $data_skills[id].sp_cost
      Action.set_outer do
        return $scene.target_action_break unless battler.movable?
        (return unless battler.sp>=100) unless cost_sp
      end
      targets = nil
      if $data_skills[id].scope == 1
        targets = select_target.call(battler,select_attack_target.call(battler,true))
      elsif $data_skills[id].scope == 2
        targets = $game_troop.enemies.find_all{|t|t.exist?}
      elsif $data_skills[id].scope == 3
        targets = select_target.call(battler,select_attack_target.call(battler,false))
      elsif $data_skills[id].scope == 4
        targets = $game_party.actors.find_all{|t|t.exist?}
      elsif $data_skills[id].scope == 5
        targets = select_target.call(battler,lambda do |target,selected|
          return if selected.length>0
          return unless target.is_a?(battler.class) or battler.is_a?(target.class)
          return target.hp0?
        end)
      elsif $data_skills[id].scope == 6
        targets = $game_party.actors.find_all{|t|t.hp0?}
      elsif $data_skills[id].scope == 7
        targets = [battler]
      else
        throw(RuntimeError,"未知的skill[#{id}].scpoe:#{$data_skills[id].scope}")
      end
      return if targets.empty?
      Action.pause($scene.target_action_start)
      battler.sp-=sp
      cost_sp = true
      block_animation.call($data_skills[id].animation1_id,[battler])
      block_animation.call($data_skills[id].animation2_id,targets)
      targets.each do |t|
        t.skill_effect(battler,$data_skills[id])
        t.show_damage
      end
    end)
  end
  define_method(:items) do |battler,id|
    return xse716_items[id].call(battler) if xse716_items[id]
    return Action.new(lambda do
      Action.pause($scene.target_action_start)
    end)
  end
#========================一般行动（攻击防御逃跑)===========================
  define_method(:attack) do |battler|
    return Action.new(lambda do
      #==============总中断条件==================
      Action.set_outer{return $scene.target_action_break if battler.restriction > 2}
      #==============选择目标====================
      targets = select_target.call(battler,select_attack_target.call(battler,true))
      return if targets.empty?#如果取消选择则返回
      Action.pause($scene.target_action_start)
      #=========播放动画并进行各种效果==========
      attack_function.call(battler,targets)#由于高度的相似性，提取了一下
    end)
  end
  guarding_battlers = []
  Game_Battler.class_eval do
    define_method(:guarding?){return guarding_battlers.include?(self)}
  end
  define_method(:guard) do |battler|
    return Action.new(lambda do
      #防御特殊之处：被打断时不进行打断结算
      Action.set_outer{return if battler.restriction>1}
      Action.pause($scene.target_action_start)
      block_animation.call(101,[battler])
      #播放动画完毕后才正式进入防御状态
      guarding_battlers.push(battler)
      Action.set{guarding_battlers.delete(battler)}
      10.times do#防御10个行动循环
        battler.at += battler.agi*2#防御期间，每次循环获得2倍at
        Action.pause
      end
    end)
  end
  define_method(:not_exist) do |battler|
    return Action.new(lambda do
      throw(RuntimeError,"对已经不在场上的#{battler.name}产生action，重新设计吧")
      Action.pause($scene.target_action_start)
    end)
  end
  define_method(:cant_action) do |battler|
    return Action.new(lambda do
      #由于某种原因不能行动，轮到battler时不能行动的状态已经解除时，解除行动
      Action.set_outer{return $scene.target_action_break unless battler.restriction == 4}
      Action.pause($scene.target_action_start)
      block_animation.call(0,[battler])
    end)
  end
  define_method(:attack_party) do |battler|
    return Action.new(lambda do
      Action.set_outer do
        return $scene.target_action_break if battler.restriction == 4
        return $scene.target_action_break if battler.restriction <= 2
      end
      targets = select_target.call(battler,select_attack_target.call(battler,false))
      return $scene.target_action_break if targets.empty?#如果无可用目标则返回
      Action.pause($scene.target_action_start)
      attack_function.call(battler,targets)
    end)
  end
  define_method(:attack_enemy) do |battler|
    return Action.new(lambda do
      Action.set_outer{return $scene.target_action_break if battler.restriction == 4}
      targets = select_target.call(battler,select_attack_target.call(battler,true))
      return $scene.target_action_break if targets.empty?#如果无可用目标则返回
      Action.pause($scene.target_action_start)
      attack_function.call(battler,targets)
    end)
  end
  define_method(:break_out) do |battler|
    #选择行动时死亡会获得此action，然而没想好做啥。。
    return Action.new(lambda do
      Action.pause($scene.target_action_start)
    end)
  end
  define_method(:do_nothing) do |battler|
    return Action.new(lambda do
      Action.set_outer do
        #不进行中断结算，假如restriction=3时会立刻攻击队友
        return if battler.restriction==3#强制攻击队友生效，强制攻击敌人不生效
        return $scene.target_action_break if battler.restriction==4#不能行动时中断。。虽然表现的差不多
      end
      Action.pause($scene.target_action_start)
    end)
  end
  define_method(:escape) do |battler|
    return Action.new(lambda do
      #由于逃跑只发生在一瞬间，set_outer就不太合适了
      return $scene.target_action_break if battler.restriction>1
      Action.pause($scene.target_action_start)
      battler.escape
      8.times{Action.pause($scene.api_target_action)}
    end)
  end
end